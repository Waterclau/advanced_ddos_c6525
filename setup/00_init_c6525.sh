#!/bin/bash
set -e

NODE_TYPE=$1

if [ -z "$NODE_TYPE" ]; then
    echo "Usage: $0 <tg|monitor|victim|controller>"
    exit 1
fi

echo "============================================"
echo "Initializing c6525-100g node as: $NODE_TYPE"
echo "============================================"

# System update
echo "[1/8] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    build-essential \
    git \
    tmux \
    htop \
    python3-pip \
    libnuma-dev \
    libpcap-dev \
    pkg-config \
    linux-headers-$(uname -r) \
    pciutils \
    lshw \
    numactl \
    wget \
    curl \
    ethtool \
    net-tools \
    iperf3 \
    tcpdump > /dev/null 2>&1

# Hugepages configuration (8GB total for 100G NIC)
echo "[2/8] Configuring hugepages (8GB)..."
mkdir -p /mnt/huge

# Allocate 4096 2MB pages per NUMA node (8GB total)
echo 4096 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages || true
echo 4096 > /sys/devices/system/node/node1/hugepages/hugepages-2048kB/nr_hugepages || true

# Make persistent
if ! grep -q "vm.nr_hugepages" /etc/sysctl.conf; then
    echo "vm.nr_hugepages=8192" >> /etc/sysctl.conf
fi

# Mount hugepages
if ! mount | grep -q "/mnt/huge"; then
    mount -t hugetlbfs nodev /mnt/huge
fi

if ! grep -q "/mnt/huge" /etc/fstab; then
    echo "nodev /mnt/huge hugetlbfs defaults 0 0" >> /etc/fstab
fi

# CPU governor to performance mode
echo "[3/8] Setting CPU to performance mode..."
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [ -f "$cpu" ]; then
        echo performance > $cpu
    fi
done

# Disable CPU frequency scaling
if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
    echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
fi

# Network tuning for 100G
echo "[4/8] Applying network tuning for 100G..."
cat >> /etc/sysctl.conf << 'EOF'

# 100G Network Tuning
net.core.rmem_max=536870912
net.core.wmem_max=536870912
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.ipv4.tcp_rmem=4096 87380 536870912
net.ipv4.tcp_wmem=4096 65536 536870912
net.core.netdev_max_backlog=300000
net.core.netdev_budget=600
net.core.netdev_budget_usecs=8000
net.core.somaxconn=8192
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.ip_local_port_range=10000 65535
net.core.optmem_max=40960000
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=1
EOF

sysctl -p > /dev/null 2>&1

# Disable IRQ balance for better performance
echo "[5/8] Disabling IRQ balance..."
systemctl stop irqbalance || true
systemctl disable irqbalance || true

# Directory structure
echo "[6/8] Creating directory structure..."
mkdir -p /local/{logs,results,pcaps,octosketch}
chmod 777 /local/{logs,results,pcaps}

# Load kernel modules for DPDK
echo "[7/8] Loading kernel modules..."
modprobe uio || true
modprobe uio_pci_generic || true

# Node-specific configuration
echo "[8/8] Applying node-specific configuration..."
case $NODE_TYPE in
    tg)
        echo "node-tg" > /etc/hostname
        hostname node-tg
        ;;
    monitor)
        echo "node-monitor" > /etc/hostname
        hostname node-monitor
        ;;
    victim)
        echo "node-victim" > /etc/hostname
        hostname node-victim
        ;;
    controller)
        echo "node-controller" > /etc/hostname
        hostname node-controller
        ;;
esac

echo ""
echo "============================================"
echo "✓ Node $NODE_TYPE initialized successfully"
echo "============================================"
echo ""
echo "System Information:"
echo "  - Total Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "  - Hugepages: $(grep HugePages_Total /proc/meminfo | awk '{print $2}') x 2MB"
echo "  - CPU Cores: $(nproc)"
echo "  - CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
echo ""
echo "Next steps:"
case $NODE_TYPE in
    monitor)
        echo "  1. Run: sudo ./setup/01_dpdk_install.sh"
        echo "  2. Run: sudo ./setup/02_octosketch_build.sh"
        ;;
    tg)
        echo "  1. Run: sudo ./setup/03_trex_setup.sh"
        ;;
    controller)
        echo "  1. Wait for monitor and tg setup to complete"
        echo "  2. Run: ./automation/run_experiment.sh"
        ;;
esac
echo ""
