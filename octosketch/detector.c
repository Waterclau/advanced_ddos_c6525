#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>
#include <rte_hash.h>
#include <rte_jhash.h>
#include <rte_cycles.h>
#include <rte_ip.h>
#include <rte_tcp.h>
#include <rte_udp.h>
#include <signal.h>
#include <time.h>
#include "attacks.h"

#define RX_RING_SIZE 4096
#define TX_RING_SIZE 4096
#define NUM_MBUFS 524288
#define MBUF_CACHE_SIZE 512
#define BURST_SIZE 128
#define SKETCH_ROWS 8
#define SKETCH_COLS 65536
#define DETECTION_THRESHOLD_MPPS 100
#define DETECTION_THRESHOLD_GBPS 50

volatile bool force_quit = false;

typedef struct {
    uint32_t src_ip;
    uint32_t dst_ip;
    uint16_t src_port;
    uint16_t dst_port;
    uint8_t proto;
} __attribute__((packed)) flow_key_t;

typedef struct {
    uint32_t sketch[SKETCH_ROWS][SKETCH_COLS];
    uint64_t total_pkts;
    uint64_t total_bytes;
    uint64_t anomaly_count;
    uint64_t syn_count;
    uint64_t udp_count;
    uint64_t icmp_count;
    uint64_t tcp_ack_count;
    uint64_t frag_count;
} detector_ctx_t;

static void signal_handler(int signum) {
    if (signum == SIGINT || signum == SIGTERM) {
        printf("\n[INFO] Signal %d received, shutting down...\n", signum);
        force_quit = true;
    }
}

static inline uint32_t sketch_hash(const flow_key_t *key, int row) {
    return rte_jhash_32b((const uint32_t *)key, sizeof(flow_key_t)/4, row + 0x9e3779b9) % SKETCH_COLS;
}

static inline void update_sketch(detector_ctx_t *ctx, const flow_key_t *key, uint32_t pkt_len) {
    for (int i = 0; i < SKETCH_ROWS; i++) {
        uint32_t pos = sketch_hash(key, i);
        __atomic_add_fetch(&ctx->sketch[i][pos], pkt_len, __ATOMIC_RELAXED);
    }
}

static inline uint32_t query_sketch(detector_ctx_t *ctx, const flow_key_t *key) {
    uint32_t min_val = UINT32_MAX;
    for (int i = 0; i < SKETCH_ROWS; i++) {
        uint32_t pos = sketch_hash(key, i);
        uint32_t val = __atomic_load_n(&ctx->sketch[i][pos], __ATOMIC_RELAXED);
        if (val < min_val) min_val = val;
    }
    return min_val;
}

static int detect_anomaly(detector_ctx_t *ctx, const flow_key_t *key, uint8_t tcp_flags) {
    uint32_t flow_bytes = query_sketch(ctx, key);
    
    // High volume attacks (>10M bytes per flow)
    if (flow_bytes > 10000000) {
        if (key->proto == IPPROTO_UDP) return ATTACK_UDP_FLOOD;
        if (key->proto == IPPROTO_ICMP) return ATTACK_ICMP_FLOOD;
        return ATTACK_VOLUMETRIC;
    }
    
    // TCP SYN flood detection
    if (key->proto == IPPROTO_TCP && (tcp_flags & 0x02) && !(tcp_flags & 0x10)) {
        if (flow_bytes > 5000000) return ATTACK_SYN_FLOOD;
    }
    
    // TCP ACK flood
    if (key->proto == IPPROTO_TCP && (tcp_flags & 0x10) && !(tcp_flags & 0x02)) {
        if (flow_bytes > 5000000) return ATTACK_ACK_FLOOD;
    }
    
    // Amplification attacks (small source, large destination)
    if (key->proto == IPPROTO_UDP) {
        if (key->dst_port == rte_cpu_to_be_16(53) && flow_bytes > 3000000) 
            return ATTACK_DNS_AMP;
        if (key->dst_port == rte_cpu_to_be_16(123) && flow_bytes > 2000000) 
            return ATTACK_NTP_AMP;
        if (key->dst_port == rte_cpu_to_be_16(1900) && flow_bytes > 2000000) 
            return ATTACK_SSDP_AMP;
    }
    
    return ATTACK_NONE;
}

static int lcore_main(void *arg) {
    detector_ctx_t *ctx = (detector_ctx_t *)arg;
    uint16_t port = 0;
    uint16_t queue = rte_lcore_id() - 1;
    
    printf("[CORE %u] Processing queue %u\n", rte_lcore_id(), queue);
    
    struct rte_mbuf *bufs[BURST_SIZE];
    uint64_t local_pkts = 0;
    uint64_t local_bytes = 0;
    
    while (!force_quit) {
        uint16_t nb_rx = rte_eth_rx_burst(port, queue, bufs, BURST_SIZE);
        
        if (unlikely(nb_rx == 0)) {
            continue;
        }
        
        for (uint16_t i = 0; i < nb_rx; i++) {
            struct rte_mbuf *m = bufs[i];
            struct rte_ether_hdr *eth = rte_pktmbuf_mtod(m, struct rte_ether_hdr *);
            
            if (eth->ether_type == rte_cpu_to_be_16(RTE_ETHER_TYPE_IPV4)) {
                struct rte_ipv4_hdr *ip = (struct rte_ipv4_hdr *)(eth + 1);
                
                flow_key_t key = {
                    .src_ip = ip->src_addr,
                    .dst_ip = ip->dst_addr,
                    .proto = ip->next_proto_id,
                    .src_port = 0,
                    .dst_port = 0
                };
                
                uint8_t tcp_flags = 0;
                
                if (ip->next_proto_id == IPPROTO_TCP) {
                    struct rte_tcp_hdr *tcp = (struct rte_tcp_hdr *)((uint8_t *)ip + ((ip->version_ihl & 0x0F) * 4));
                    key.src_port = tcp->src_port;
                    key.dst_port = tcp->dst_port;
                    tcp_flags = tcp->tcp_flags;
                    
                    if (tcp_flags & 0x02) __atomic_add_fetch(&ctx->syn_count, 1, __ATOMIC_RELAXED);
                    if (tcp_flags & 0x10) __atomic_add_fetch(&ctx->tcp_ack_count, 1, __ATOMIC_RELAXED);
                    
                } else if (ip->next_proto_id == IPPROTO_UDP) {
                    struct rte_udp_hdr *udp = (struct rte_udp_hdr *)((uint8_t *)ip + ((ip->version_ihl & 0x0F) * 4));
                    key.src_port = udp->src_port;
                    key.dst_port = udp->dst_port;
                    __atomic_add_fetch(&ctx->udp_count, 1, __ATOMIC_RELAXED);
                    
                } else if (ip->next_proto_id == IPPROTO_ICMP) {
                    __atomic_add_fetch(&ctx->icmp_count, 1, __ATOMIC_RELAXED);
                }
                
                // Check for fragmentation
                uint16_t frag_offset = rte_be_to_cpu_16(ip->fragment_offset);
                if ((frag_offset & 0x3FFF) != 0 || (frag_offset & 0x2000) != 0) {
                    __atomic_add_fetch(&ctx->frag_count, 1, __ATOMIC_RELAXED);
                }
                
                // Update sketch
                update_sketch(ctx, &key, m->pkt_len);
                
                // Detect anomaly
                int anomaly = detect_anomaly(ctx, &key, tcp_flags);
                if (anomaly != ATTACK_NONE) {
                    __atomic_add_fetch(&ctx->anomaly_count, 1, __ATOMIC_RELAXED);
                }
                
                local_pkts++;
                local_bytes += m->pkt_len;
            }
            
            rte_pktmbuf_free(m);
        }
        
        // Update global counters periodically
        if (unlikely((local_pkts & 0xFFF) == 0)) {
            __atomic_add_fetch(&ctx->total_pkts, local_pkts, __ATOMIC_RELAXED);
            __atomic_add_fetch(&ctx->total_bytes, local_bytes, __ATOMIC_RELAXED);
            local_pkts = 0;
            local_bytes = 0;
        }
    }
    
    // Final update
    __atomic_add_fetch(&ctx->total_pkts, local_pkts, __ATOMIC_RELAXED);
    __atomic_add_fetch(&ctx->total_bytes, local_bytes, __ATOMIC_RELAXED);
    
    return 0;
}

int main(int argc, char *argv[]) {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    printf("\n");
    printf("╔══════════════════════════════════════════════╗\n");
    printf("║   OctoSketch DPDK DDoS Detector v2.0        ║\n");
    printf("║   Optimized for c6525-100g (100 Gbps)       ║\n");
    printf("╚══════════════════════════════════════════════╝\n");
    printf("\n");
    
    int ret = rte_eal_init(argc, argv);
    if (ret < 0) rte_exit(EXIT_FAILURE, "EAL initialization failed\n");
    
    uint16_t nb_ports = rte_eth_dev_count_avail();
    if (nb_ports == 0) rte_exit(EXIT_FAILURE, "No Ethernet ports available\n");
    
    printf("[INFO] Found %u port(s)\n", nb_ports);
    
    // Create mbuf pool
    struct rte_mempool *mbuf_pool = rte_pktmbuf_pool_create("MBUF_POOL", NUM_MBUFS,
        MBUF_CACHE_SIZE, 0, RTE_MBUF_DEFAULT_BUF_SIZE, rte_socket_id());
    
    if (mbuf_pool == NULL) rte_exit(EXIT_FAILURE, "Cannot create mbuf pool\n");
    
    // Configure port for 100G with RSS
    struct rte_eth_conf port_conf = {
        .rxmode = {
            .mq_mode = RTE_ETH_MQ_RX_RSS,
            .offloads = RTE_ETH_RX_OFFLOAD_CHECKSUM | RTE_ETH_RX_OFFLOAD_RSS_HASH,
        },
        .rx_adv_conf = {
            .rss_conf = {
                .rss_key = NULL,
                .rss_hf = RTE_ETH_RSS_IP | RTE_ETH_RSS_TCP | RTE_ETH_RSS_UDP,
            },
        },
        .txmode = {
            .mq_mode = RTE_ETH_MQ_TX_NONE,
        },
    };
    
    uint16_t port = 0;
    uint16_t nb_queues = rte_lcore_count() - 1;
    
    if (nb_queues == 0) rte_exit(EXIT_FAILURE, "Need at least 2 cores (1 main + 1 worker)\n");
    
    printf("[INFO] Configuring port 0 with %u RX queues\n", nb_queues);
    
    ret = rte_eth_dev_configure(port, nb_queues, 1, &port_conf);
    if (ret < 0) rte_exit(EXIT_FAILURE, "Cannot configure port %u: %s\n", port, rte_strerror(-ret));
    
    // Setup RX queues
    for (uint16_t q = 0; q < nb_queues; q++) {
        ret = rte_eth_rx_queue_setup(port, q, RX_RING_SIZE,
                rte_eth_dev_socket_id(port), NULL, mbuf_pool);
        if (ret < 0) rte_exit(EXIT_FAILURE, "Cannot setup RX queue %u: %s\n", q, rte_strerror(-ret));
    }
    
    // Setup TX queue
    ret = rte_eth_tx_queue_setup(port, 0, TX_RING_SIZE,
            rte_eth_dev_socket_id(port), NULL);
    if (ret < 0) rte_exit(EXIT_FAILURE, "Cannot setup TX queue: %s\n", rte_strerror(-ret));
    
    // Start port
    ret = rte_eth_dev_start(port);
    if (ret < 0) rte_exit(EXIT_FAILURE, "Cannot start port: %s\n", rte_strerror(-ret));
    
    // Enable promiscuous mode
    ret = rte_eth_promiscuous_enable(port);
    if (ret != 0) printf("[WARN] Cannot enable promiscuous mode: %s\n", rte_strerror(-ret));
    
    // Initialize detector context
    detector_ctx_t ctx = {0};
    
    printf("\n[INFO] Starting detection with %u worker cores...\n\n", nb_queues);
    
    // Launch worker cores
    unsigned lcore_id;
    RTE_LCORE_FOREACH_WORKER(lcore_id) {
        rte_eal_remote_launch(lcore_main, &ctx, lcore_id);
    }
    
    // Stats collection on main core
    uint64_t last_pkts = 0, last_bytes = 0;
    time_t start_time = time(NULL);
    
    FILE *log = fopen("/local/logs/detection.log", "w");
    if (log) {
        fprintf(log, "timestamp,pps,gbps,anomalies,syn,udp,icmp,ack,frag\n");
        fflush(log);
    }
    
    printf("%-20s %15s %10s %10s %10s %10s %10s %10s %10s\n",
           "Time", "PPS", "Gbps", "Anomaly", "SYN", "UDP", "ICMP", "ACK", "Frag");
    printf("────────────────────────────────────────────────────────────────────────────────────────────────────\n");
    
    while (!force_quit) {
        sleep(1);
        
        uint64_t pkts = __atomic_load_n(&ctx.total_pkts, __ATOMIC_RELAXED);
        uint64_t bytes = __atomic_load_n(&ctx.total_bytes, __ATOMIC_RELAXED);
        uint64_t anomalies = __atomic_load_n(&ctx.anomaly_count, __ATOMIC_RELAXED);
        uint64_t syn = __atomic_load_n(&ctx.syn_count, __ATOMIC_RELAXED);
        uint64_t udp = __atomic_load_n(&ctx.udp_count, __ATOMIC_RELAXED);
        uint64_t icmp = __atomic_load_n(&ctx.icmp_count, __ATOMIC_RELAXED);
        uint64_t ack = __atomic_load_n(&ctx.tcp_ack_count, __ATOMIC_RELAXED);
        uint64_t frag = __atomic_load_n(&ctx.frag_count, __ATOMIC_RELAXED);
        
        uint64_t pps = pkts - last_pkts;
        uint64_t bps = (bytes - last_bytes) * 8;
        double gbps = bps / 1e9;
        
        time_t elapsed = time(NULL) - start_time;
        
        if (log) {
            fprintf(log, "%lu,%lu,%.2f,%lu,%lu,%lu,%lu,%lu,%lu\n", 
                    time(NULL), pps, gbps, anomalies, syn, udp, icmp, ack, frag);
            fflush(log);
        }
        
        printf("%-20ld %15lu %10.2f %10lu %10lu %10lu %10lu %10lu %10lu\n",
               elapsed, pps, gbps, anomalies, syn, udp, icmp, ack, frag);
        
        // Alert on high rate attacks
        if (pps > DETECTION_THRESHOLD_MPPS * 1000000 || gbps > DETECTION_THRESHOLD_GBPS) {
            printf("[ALERT] High rate detected! PPS: %lu M, Gbps: %.2f\n", pps/1000000, gbps);
        }
        
        last_pkts = pkts;
        last_bytes = bytes;
    }
    
    if (log) fclose(log);
    
    printf("\n[INFO] Waiting for worker cores to finish...\n");
    
    RTE_LCORE_FOREACH_WORKER(lcore_id) {
        rte_eal_wait_lcore(lcore_id);
    }
    
    printf("[INFO] Stopping port...\n");
    rte_eth_dev_stop(port);
    rte_eth_dev_close(port);
    
    printf("\n");
    printf("╔══════════════════════════════════════════════╗\n");
    printf("║          Detection Summary                   ║\n");
    printf("╠══════════════════════════════════════════════╣\n");
    printf("║ Total Packets:    %20lu ║\n", ctx.total_pkts);
    printf("║ Total Bytes:      %20lu ║\n", ctx.total_bytes);
    printf("║ Anomalies:        %20lu ║\n", ctx.anomaly_count);
    printf("║ SYN Packets:      %20lu ║\n", ctx.syn_count);
    printf("║ UDP Packets:      %20lu ║\n", ctx.udp_count);
    printf("║ ICMP Packets:     %20lu ║\n", ctx.icmp_count);
    printf("╚══════════════════════════════════════════════╝\n");
    printf("\n");
    
    return 0;
}
