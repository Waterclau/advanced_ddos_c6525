#!/bin/bash
set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║    Advanced DDoS Detection Experiment Runner              ║"
echo "║    Automated testing of 9 attack types                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Configuration
RESULTS_DIR="/local/results/exp_$(date +%s)"
DURATION=60  # seconds per attack
COOLDOWN=10  # seconds between attacks

# Node hostnames (update if different)
NODE_MONITOR="node-monitor"
NODE_TG="node-tg"
NODE_VICTIM="node-victim"

# Attack list
ATTACKS=(
    "syn_flood:50"
    "udp_flood:80"
    "dns_amp:40"
    "ntp_amp:35"
    "http_flood:10"
    "icmp_flood:30"
    "fragmentation:20"
    "ack_flood:45"
    "volumetric:95"
)

echo "[INFO] Creating results directory: $RESULTS_DIR"
mkdir -p $RESULTS_DIR

# Generate attack profiles if not present
echo "[INFO] Generating attack profiles..."
ssh $NODE_TG "cd /local/exp/attacks && python3 generate_attacks.py"

# Start detector on monitor node
echo "[INFO] Starting OctoSketch detector on $NODE_MONITOR..."
ssh $NODE_MONITOR "source /etc/profile.d/dpdk.sh && cd /local/octosketch && sudo ./octosketch_detector -l 1-16 --log-level=7 -- -p 0x1 > $RESULTS_DIR/detector.log 2>&1 &"

echo "[INFO] Waiting for detector to initialize..."
sleep 10

# Verify detector is running
if ssh $NODE_MONITOR "pgrep octosketch_detector > /dev/null"; then
    echo "✓ Detector is running"
else
    echo "✗ ERROR: Detector failed to start"
    echo "  Check logs: ssh $NODE_MONITOR 'cat $RESULTS_DIR/detector.log'"
    exit 1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              Starting Attack Sequence                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

ATTACK_NUM=1
TOTAL_ATTACKS=${#ATTACKS[@]}

for attack_spec in "${ATTACKS[@]}"; do
    IFS=':' read -r attack_name rate_gbps <<< "$attack_spec"
    
    echo "────────────────────────────────────────────────────────────"
    echo "[$ATTACK_NUM/$TOTAL_ATTACKS] Running: $attack_name (${rate_gbps} Gbps)"
    echo "────────────────────────────────────────────────────────────"
    
    # Start timestamp
    start_time=$(date +%s)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attack started: $attack_name" | tee -a $RESULTS_DIR/timeline.log
    
    # Launch attack from TRex
    ssh $NODE_TG "cd /local/v3.05 && sudo ./t-rex-64 -f /local/exp/attacks/${attack_name}.yaml -d $DURATION -m $rate_gbps > /tmp/trex_${attack_name}.log 2>&1" &
    TREX_PID=$!
    
    # Monitor attack in real-time
    echo "[INFO] Monitoring for $DURATION seconds..."
    
    for i in $(seq 1 $DURATION); do
        # Get latest detection stats
        if ssh $NODE_MONITOR "tail -1 /local/logs/detection.log" > /tmp/last_stat.txt 2>/dev/null; then
            stats=$(cat /tmp/last_stat.txt)
            echo -ne "\r  [${i}s/${DURATION}s] $stats                    "
        fi
        sleep 1
    done
    echo ""
    
    # Wait for TRex to finish
    wait $TREX_PID
    
    # End timestamp
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attack completed: $attack_name (${duration}s)" | tee -a $RESULTS_DIR/timeline.log
    
    # Collect TRex logs
    ssh $NODE_TG "cat /tmp/trex_${attack_name}.log" > $RESULTS_DIR/trex_${attack_name}.log
    
    # Cooldown between attacks
    if [ $ATTACK_NUM -lt $TOTAL_ATTACKS ]; then
        echo "[INFO] Cooldown period: ${COOLDOWN}s..."
        sleep $COOLDOWN
    fi
    
    echo "✓ Attack $ATTACK_NUM/$TOTAL_ATTACKS completed"
    echo ""
    
    ATTACK_NUM=$((ATTACK_NUM + 1))
done

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║            Stopping Detector & Collecting Results         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Stop detector
echo "[INFO] Stopping detector..."
ssh $NODE_MONITOR "sudo pkill octosketch_detector"
sleep 2

# Collect all logs
echo "[INFO] Collecting logs from nodes..."
scp $NODE_MONITOR:/local/logs/detection.log $RESULTS_DIR/
scp $NODE_MONITOR:$RESULTS_DIR/detector.log $RESULTS_DIR/ 2>/dev/null || true

echo "[INFO] Generating summary..."

# Generate summary statistics
cat > $RESULTS_DIR/summary.txt << EOF
╔═══════════════════════════════════════════════════════════╗
║           DDoS Detection Experiment Summary                ║
╚═══════════════════════════════════════════════════════════╝

Experiment ID: exp_$(basename $RESULTS_DIR)
Start Time: $(head -1 $RESULTS_DIR/timeline.log | cut -d']' -f1 | tr -d '[')
End Time: $(tail -1 $RESULTS_DIR/timeline.log | cut -d']' -f1 | tr -d '[')
Duration: $(($(tail -1 $RESULTS_DIR/timeline.log | cut -d'[' -f2 | cut -d']' -f1 | xargs -I{} date -d "{}" +%s) - $(head -1 $RESULTS_DIR/timeline.log | cut -d'[' -f2 | cut -d']' -f1 | xargs -I{} date -d "{}" +%s)))s

Attacks Executed: $TOTAL_ATTACKS

Attack Summary:
EOF

for attack_spec in "${ATTACKS[@]}"; do
    IFS=':' read -r attack_name rate_gbps <<< "$attack_spec"
    echo "  - $attack_name: ${rate_gbps} Gbps for ${DURATION}s" >> $RESULTS_DIR/summary.txt
done

# Parse detection log for statistics
if [ -f "$RESULTS_DIR/detection.log" ]; then
    echo "" >> $RESULTS_DIR/summary.txt
    echo "Detection Statistics:" >> $RESULTS_DIR/summary.txt
    
    total_lines=$(wc -l < $RESULTS_DIR/detection.log)
    total_anomalies=$(awk -F',' 'NR>1 {sum+=$4} END {print sum}' $RESULTS_DIR/detection.log)
    max_pps=$(awk -F',' 'NR>1 {if($2>max) max=$2} END {print max}' $RESULTS_DIR/detection.log)
    max_gbps=$(awk -F',' 'NR>1 {if($3>max) max=$3} END {print max}' $RESULTS_DIR/detection.log)
    
    echo "  Total Samples: $total_lines" >> $RESULTS_DIR/summary.txt
    echo "  Total Anomalies Detected: $total_anomalies" >> $RESULTS_DIR/summary.txt
    echo "  Peak PPS: $max_pps" >> $RESULTS_DIR/summary.txt
    echo "  Peak Throughput: ${max_gbps} Gbps" >> $RESULTS_DIR/summary.txt
fi

echo "" >> $RESULTS_DIR/summary.txt
echo "Results Location: $RESULTS_DIR" >> $RESULTS_DIR/summary.txt
echo "═══════════════════════════════════════════════════════════" >> $RESULTS_DIR/summary.txt

# Display summary
cat $RESULTS_DIR/summary.txt

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                  Experiment Complete!                      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "View detection log:"
echo "  cat $RESULTS_DIR/detection.log | column -t -s,"
echo ""
echo "View summary:"
echo "  cat $RESULTS_DIR/summary.txt"
echo ""
echo "View timeline:"
echo "  cat $RESULTS_DIR/timeline.log"
echo ""
