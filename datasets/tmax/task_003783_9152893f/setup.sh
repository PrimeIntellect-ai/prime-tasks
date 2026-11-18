#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    # Install Go 1.20
    wget https://go.dev/dl/go1.20.14.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.20.14.linux-amd64.tar.gz
    rm go1.20.14.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/bin/go
    ln -s /usr/local/go/bin/gofmt /usr/bin/gofmt

    # Create directories
    mkdir -p /home/user/uptime-app/logs

    # Create go.mod
    cat << 'EOF' > /home/user/uptime-app/go.mod
module uptime-app

go 1.20
EOF

    # Create calc.go
    cat << 'EOF' > /home/user/uptime-app/calc.go
package calc

import (
	"strconv"
	"strings"
)

// ParseMetric converts a string metric to float32
func ParseMetric(val string) (float32, error) {
	val = strings.TrimSuffix(val, "%")
	f, err := strconv.ParseFloat(val, 32)
	if err != nil {
		return 0, err
	}
	return float32(f), nil
}

// CalculateAverage averages the metrics
func CalculateAverage(metrics []float32) float32 {
	var sum float32
	for _, m := range metrics {
		sum += m
	}
	if len(metrics) == 0 {
		return 0
	}
	return sum / float32(len(metrics))
}
EOF

    # Generate raw_metrics.txt
    python3 -c "
import os
with open('/home/user/uptime-app/logs/raw_metrics.txt', 'w') as f:
    for _ in range(50000):
        f.write('99.990%\n')
    for _ in range(49995):
        f.write('99.999%\n')
    f.write('  99.999 %\n')
    f.write('99.999% \n')
    f.write('\t99.999%\n')
    f.write(' 99.999\n')
    f.write('99.999 % \n')
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
