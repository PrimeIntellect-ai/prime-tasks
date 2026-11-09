#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/logs/node_1.log
INFO [2023-10-25 10:00:01] Starting packet processor
INFO [2023-10-25 10:00:02] Received packet: 010002AABB
INFO [2023-10-25 10:00:03] Processed 1 packets successfully.
EOF

    cat << 'EOF' > /home/user/logs/node_2.log
INFO [2023-10-25 10:00:01] Starting packet processor
INFO [2023-10-25 10:00:02] Received packet: 02000411223344
INFO [2023-10-25 10:00:03] Processed 1 packets successfully.
EOF

    cat << 'EOF' > /home/user/logs/node_3.log
INFO [2023-10-25 10:00:01] Starting packet processor
INFO [2023-10-25 10:00:02] Received packet: 010002AABB
INFO [2023-10-25 10:00:03] Received packet: 0301f10a0b0c0d0e
PANIC [2023-10-25 10:00:04] panic: runtime error: slice bounds out of range [3:500] with capacity 8
goroutine 1 [running]:
parser.ParsePacket(...)
	/home/user/project/parser.go:12
FATAL: crashing payload hex: 0301f10a0b0c0d0e
EOF

    cat << 'EOF' > /home/user/logs/node_4.log
INFO [2023-10-25 10:00:01] Starting packet processor
INFO [2023-10-25 10:00:02] Received packet: 010001FF
EOF

    cd /home/user/project
    go mod init packetparser

    cat << 'EOF' > /home/user/project/parser.go
package parser

import (
	"encoding/binary"
	"errors"
)

// ParsePacket parses a simple TLV (Type-Length-Value) packet.
func ParsePacket(data []byte) (byte, []byte, error) {
	if len(data) < 3 {
		return 0, nil, errors.New("packet too short")
	}
	pktType := data[0]
	length := binary.BigEndian.Uint16(data[1:3])

	// BUG: Does not check if length + 3 exceeds len(data)
	value := data[3 : 3+length]

	return pktType, value, nil
}
EOF

    cat << 'EOF' > /home/user/project/parser_test.go
package parser

import (
	"testing"
)

func FuzzParsePacket(f *testing.F) {
	f.Add([]byte{0x01, 0x00, 0x02, 0xAA, 0xBB})
	f.Fuzz(func(t *testing.T, data []byte) {
		ParsePacket(data) // should not panic
	})
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
