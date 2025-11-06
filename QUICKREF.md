# ⚡ QUICK REFERENCE CARD

## Complete Setup (30 minutes)

### 1. ALL NODES (parallel)
```bash
cd /local/exp
sudo ./setup/00_init_c6525.sh tg         # node-tg
sudo ./setup/00_init_c6525.sh monitor    # node-monitor
sudo ./setup/00_init_c6525.sh victim     # node-victim
sudo ./setup/00_init_c6525.sh controller # node-controller
```

### 2. NODE-MONITOR ONLY
```bash
sudo ./setup/01_dpdk_install.sh
source /etc/profile.d/dpdk.sh
export IFACE_PCI="0000:XX:00.0"  # YOUR PCI ADDRESS
sudo $RTE_SDK/usertools/dpdk-devbind.py --bind=uio_pci_generic $IFACE_PCI
sudo ./setup/02_octosketch_build.sh
```

### 3. NODE-TG ONLY
```bash
sudo ./setup/03_trex_setup.sh
```

### 4. RUN EXPERIMENT (node-controller)
```bash
./automation/run_experiment.sh
```

---

## Key Commands

### Check DPDK binding
```bash
$RTE_SDK/usertools/dpdk-devbind.py --status
```

### Manual detector start
```bash
cd /local/octosketch
sudo ./run_detector.sh
```

### Manual attack test
```bash
cd /local/v3.05
sudo ./t-rex-64 -f /local/exp/attacks/syn_flood.yaml -m 50 -d 60
```

### View live logs
```bash
tail -f /local/logs/detection.log
```

### Results location
```bash
ls -la /local/results/exp_*/
```

---

## Troubleshooting

**DPDK compile failed:**
```bash
cd /local/dpdk && rm -rf build && meson setup build && cd build && ninja
```

**Interface won't bind:**
```bash
sudo modprobe uio_pci_generic
sudo $RTE_SDK/usertools/dpdk-devbind.py --unbind $IFACE_PCI
sudo $RTE_SDK/usertools/dpdk-devbind.py --bind=uio_pci_generic $IFACE_PCI
```

**Detector shows 0 packets:**
```bash
# Check interface is bound to DPDK first!
$RTE_SDK/usertools/dpdk-devbind.py --status
```

**Need more hugepages:**
```bash
sudo sysctl -w vm.nr_hugepages=8192
sudo umount /mnt/huge && sudo mount -t hugetlbfs nodev /mnt/huge
```

---

## Attack Types (9 total)

1. SYN Flood - 50 Gbps
2. UDP Flood - 80 Gbps
3. DNS Amplification - 40 Gbps
4. NTP Amplification - 35 Gbps
5. HTTP Flood - 10 Gbps
6. ICMP Flood - 30 Gbps
7. IP Fragmentation - 20 Gbps
8. ACK Flood - 45 Gbps
9. Volumetric Mixed - 95 Gbps

Total experiment time: ~15 minutes (60s × 9 attacks + 10s cooldown)

---

## File Locations

- Setup scripts: `/local/exp/setup/`
- Detector source: `/local/exp/octosketch/`
- Attack profiles: `/local/exp/attacks/`
- Compiled detector: `/local/octosketch/`
- DPDK: `/local/dpdk/`
- TRex: `/local/v3.05/`
- Logs: `/local/logs/`
- Results: `/local/results/exp_<timestamp>/`

---

**Full Guide:** See EXECUTE.md for detailed instructions
