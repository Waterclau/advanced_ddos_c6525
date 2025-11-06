# Advanced DDoS Detection Experiment - CloudLab c6525-100g

High-performance DDoS detection system using DPDK and OctoSketch on 100 Gbps infrastructure.

## Quick Start

```bash
# On ALL nodes:
cd /local/exp
sudo ./setup/00_init_c6525.sh <node_type>

# On node-monitor:
sudo ./setup/01_dpdk_install.sh
sudo ./setup/02_octosketch_build.sh

# On node-tg:
sudo ./setup/03_trex_setup.sh

# On node-controller:
./automation/run_experiment.sh
```

## Contents

- **setup/** - Installation scripts for DPDK, OctoSketch, and TRex
- **octosketch/** - DPDK-based detector source code
- **attacks/** - Attack profile generator (9 attack types)
- **automation/** - Experiment orchestration scripts
- **EXECUTE.md** - Complete execution guide with troubleshooting

## Features

- 100 Gbps line-rate detection
- 9 attack types (SYN flood, UDP flood, DNS amp, NTP amp, HTTP flood, ICMP flood, fragmentation, ACK flood, volumetric)
- Real-time anomaly detection with Count-Min Sketch
- Multi-core packet processing (16 cores)
- Automated experiment workflow

## Requirements

- 4x CloudLab c6525-100g nodes
- Ubuntu 22.04/24.04
- 100G network interfaces
- 8GB hugepages per node

## Support

See **EXECUTE.md** for detailed instructions and troubleshooting.

## License

MIT
