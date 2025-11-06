#!/bin/bash
set -e

echo "=========================================="
echo "Building OctoSketch DPDK Detector"
echo "=========================================="

# Source DPDK environment
source /etc/profile.d/dpdk.sh

# Verify DPDK is installed
if ! pkg-config --exists libdpdk; then
    echo "ERROR: DPDK not found. Run 01_dpdk_install.sh first"
    exit 1
fi

# Create build directory
mkdir -p /local/octosketch
cd /local/octosketch

# Copy source files from repository
echo "[1/3] Copying source files..."
cp /local/exp/octosketch/detector.c .
cp /local/exp/octosketch/attacks.h .
cp /local/exp/octosketch/Makefile .

# Build
echo "[2/3] Compiling detector..."
make clean
make -j $(nproc)

# Verify build
if [ ! -f "octosketch_detector" ]; then
    echo "ERROR: Build failed"
    exit 1
fi

# Create run script
echo "[3/3] Creating run script..."
cat > run_detector.sh << 'EOF'
#!/bin/bash

# Source DPDK environment
source /etc/profile.d/dpdk.sh

# Create log directory
mkdir -p /local/logs

# Run detector with 16 cores (adjust based on your system)
# Core 0: Main thread
# Cores 1-16: Packet processing
sudo ./octosketch_detector -l 1-16 --log-level=7 -- -p 0x1

EOF

chmod +x run_detector.sh

echo ""
echo "=========================================="
echo "✓ OctoSketch detector built successfully"
echo "=========================================="
echo ""
echo "Binary size: $(du -h octosketch_detector | cut -f1)"
echo ""
echo "To run the detector:"
echo "  cd /local/octosketch"
echo "  sudo ./run_detector.sh"
echo ""
echo "Logs will be saved to: /local/logs/detection.log"
echo ""
