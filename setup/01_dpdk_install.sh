#!/bin/bash
set -e

echo "=========================================="
echo "Installing DPDK 23.11 for c6525-100g"
echo "=========================================="

cd /local

# Download DPDK if not present
if [ ! -f "dpdk-23.11.tar.xz" ]; then
    echo "[1/6] Downloading DPDK 23.11..."
    wget -q http://fast.dpdk.org/rel/dpdk-23.11.tar.xz
fi

# Extract
if [ ! -d "dpdk" ]; then
    echo "[2/6] Extracting DPDK..."
    tar xf dpdk-23.11.tar.xz
    mv dpdk-stable-23.11 dpdk
fi

cd dpdk

# Install build dependencies
echo "[3/6] Installing build dependencies..."
apt-get install -y -qq \
    meson \
    ninja-build \
    python3-pyelftools \
    python3-pip \
    libnuma-dev \
    libpcap-dev \
    pkg-config > /dev/null 2>&1

# Configure DPDK build optimized for c6525-100g (AMD EPYC)
echo "[4/6] Configuring DPDK build..."
meson setup build \
    -Dplatform=generic \
    -Dmax_lcores=128 \
    -Dmax_numa_nodes=2 \
    -Denable_kmods=false \
    -Dtests=false \
    -Dexamples=l2fwd,l3fwd \
    -Ddisable_drivers=crypto/*,baseband/*,event/* \
    -Dprefix=/usr/local \
    --buildtype=release

# Compile (use all cores)
echo "[5/6] Compiling DPDK (this takes ~10 minutes)..."
cd build
ninja -j $(nproc)

# Install
echo "[6/6] Installing DPDK..."
ninja install
ldconfig

# Setup environment variables
cat > /etc/profile.d/dpdk.sh << 'EOF'
export RTE_SDK=/local/dpdk
export RTE_TARGET=build
export PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/usr/local/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
EOF

# Source environment
source /etc/profile.d/dpdk.sh

# Verify installation
echo ""
echo "=========================================="
echo "✓ DPDK 23.11 installed successfully"
echo "=========================================="
echo ""
echo "Verification:"
pkg-config --modversion libdpdk
echo ""

echo "Available network interfaces:"
$RTE_SDK/usertools/dpdk-devbind.py --status

echo ""
echo "=========================================="
echo "IMPORTANT: Next Steps"
echo "=========================================="
echo ""
echo "1. Identify your 100G data interface PCI address:"
echo "   $RTE_SDK/usertools/dpdk-devbind.py --status"
echo ""
echo "2. Bind interface to DPDK (⚠️  will disconnect from kernel!):"
echo "   export IFACE_PCI=\"0000:XX:00.0\"  # Your PCI address"
echo "   sudo \$RTE_SDK/usertools/dpdk-devbind.py --bind=uio_pci_generic \$IFACE_PCI"
echo ""
echo "3. Verify binding:"
echo "   sudo \$RTE_SDK/usertools/dpdk-devbind.py --status"
echo ""
echo "4. Continue to OctoSketch build:"
echo "   sudo ./setup/02_octosketch_build.sh"
echo ""
