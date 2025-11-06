#ifndef ATTACKS_H
#define ATTACKS_H

// Attack type definitions
#define ATTACK_NONE             0
#define ATTACK_SYN_FLOOD        1
#define ATTACK_UDP_FLOOD        2
#define ATTACK_ICMP_FLOOD       3
#define ATTACK_HTTP_FLOOD       4
#define ATTACK_DNS_AMP          5
#define ATTACK_NTP_AMP          6
#define ATTACK_SSDP_AMP         7
#define ATTACK_MEMCACHED_AMP    8
#define ATTACK_ACK_FLOOD        9
#define ATTACK_RST_FLOOD        10
#define ATTACK_FIN_FLOOD        11
#define ATTACK_FRAGMENTATION    12
#define ATTACK_SLOWLORIS        13
#define ATTACK_RUDY             14
#define ATTACK_VOLUMETRIC       15

// Attack name mapping
static const char* attack_names[] = {
    "NONE",
    "SYN_FLOOD",
    "UDP_FLOOD",
    "ICMP_FLOOD",
    "HTTP_FLOOD",
    "DNS_AMPLIFICATION",
    "NTP_AMPLIFICATION",
    "SSDP_AMPLIFICATION",
    "MEMCACHED_AMPLIFICATION",
    "ACK_FLOOD",
    "RST_FLOOD",
    "FIN_FLOOD",
    "IP_FRAGMENTATION",
    "SLOWLORIS",
    "RUDY",
    "VOLUMETRIC_MIXED"
};

#endif // ATTACKS_H
