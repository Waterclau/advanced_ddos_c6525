#!/bin/bash
set -e

echo "=========================================="
echo "Installing TRex Traffic Generator v3.05"
echo "=========================================="

cd /local

# Download TRex
if [ ! -f "v3.05.tar.gz" ]; then
    echo "[1/4] Downloading TRex v3.05..."
    wget -q --no-cache https://trex-tgn.cisco.com/trex/release/v3.05.tar.gz
fi

# Extract
if [ ! -d "v3.05" ]; then
    echo "[2/4] Extracting TRex..."
    tar xzf v3.05.tar.gz
fi

cd v3.05

# Auto-detect 100G interface
echo "[3/4] Auto-detecting network interface..."
IFACE=$(ip -o link show | grep "state UP" | grep -v "lo" | head -1 | awk '{print $2}' | tr -d ':')

if [ -z "$IFACE" ]; then
    echo "ERROR: No active network interface found"
    exit 1
fi

IFACE_MAC=$(ip link show $IFACE | grep "link/ether" | awk '{print $2}')
IFACE_PCI=$(ethtool -i $IFACE 2>/dev/null | grep "bus-info" | awk '{print $2}')

if [ -z "$IFACE_PCI" ]; then
    # Fallback: use lshw
    IFACE_PCI=$(lshw -c network -businfo 2>/dev/null | grep "$IFACE" | awk '{print $1}' | cut -d'@' -f2)
fi

echo "Detected interface:"
echo "  Name: $IFACE"
echo "  MAC: $IFACE_MAC"
echo "  PCI: $IFACE_PCI"

# Generate TRex configuration
echo "[4/4] Generating TRex configuration..."
cat > /etc/trex_cfg.yaml << EOF
### TRex configuration for c6525-100g
- version: 2
  interfaces: ["$IFACE_PCI"]
  port_info:
    - dest_mac: [0xff,0xff,0xff,0xff,0xff,0xff]  # Broadcast (will be updated)
      src_mac: [$(echo $IFACE_MAC | sed 's/:/, 0x/g' | sed 's/^/0x/')]
  
  platform:
    master_thread_id: 0
    latency_thread_id: 1
    dual_if:
      - socket: 0
        threads: [2,3,4,5,6,7,8,9,10,11,12,13,14,15]
  
  # Memory configuration
  memory:
    mbuf_64: 32768
    mbuf_128: 32768
    mbuf_256: 16384
    mbuf_512: 16384
    mbuf_1024: 8192
    mbuf_2048: 8192
  
  # Port bandwidth limit (100G)
  port_bandwidth_gb: 100
EOF

echo ""
echo "=========================================="
echo "✓ TRex v3.05 installed successfully"
echo "=========================================="
echo ""
echo "Configuration saved to: /etc/trex_cfg.yaml"
echo ""
echo "To test TRex:"
echo "  cd /local/v3.05"
echo "  sudo ./t-rex-64 -i"
echo ""
echo "To run a simple test (10 Gbps for 30 seconds):"
echo "  sudo ./t-rex-64 -f cap2/dns.yaml -m 10 -d 30"
echo ""
