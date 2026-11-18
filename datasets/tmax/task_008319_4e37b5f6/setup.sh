#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tcpdump tshark
    pip3 install pytest scapy

    mkdir -p /home/user/statscalc
    cat << 'EOF' > /home/user/statscalc/main.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var sum, sumSq float32
	var count float32

	for scanner.Scan() {
		val, err := strconv.ParseFloat(scanner.Text(), 32)
		if err != nil {
			continue
		}
		f := float32(val)
		sum += f
		sumSq += f * f
		count++
	}

	variance := (sumSq - (sum*sum)/count) / count
	stddev := math.Sqrt(float64(variance))
	fmt.Printf("%.4f\n", stddev)
}
EOF

    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *
import struct

values = [10000.01, 10000.02, 10000.03, 10000.04, 10000.05]
packets = []
for v in values:
    payload = struct.pack('>f', v)
    pkt = IP(dst="192.168.1.100")/UDP(sport=12345, dport=9000)/Raw(load=payload)
    packets.append(pkt)

# Add some noise on other ports
pkt_noise = IP(dst="192.168.1.100")/UDP(sport=12345, dport=8000)/Raw(load=b"ignore")
packets.insert(2, pkt_noise)

wrpcap('/home/user/telemetry.pcap', packets)
EOF
    python3 /tmp/gen_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
