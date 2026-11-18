#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy.go
package main

import (
	"encoding/csv"
	"fmt"
	"os"
	"strconv"
)

func main() {
	reader := csv.NewReader(os.Stdin)
	records, err := reader.ReadAll()
	if err != nil || len(records) == 0 {
		return
	}

	headers := records[0]
	if len(headers) < 1 || headers[0] != "host" {
		return
	}

	for _, row := range records[1:] {
		if len(row) == 0 {
			continue
		}
		host := row[0]
		for i := 1; i < len(row) && i < len(headers); i++ {
			metricName := headers[i]
			value := row[i]
			severity := "UNKNOWN"
			if val, err := strconv.Atoi(value); err == nil {
				if val < 20 {
					severity = "LOW"
				} else if val <= 80 {
					severity = "NORMAL"
				} else {
					severity = "CRITICAL"
				}
			}

			fmt.Printf("[TRANSFER]\n")
			fmt.Printf("Dest: sftp://data-lake.internal/ingest/%s/%s.log\n", host, metricName)
			fmt.Printf("Payload:\n")
			fmt.Printf("<<TEMPLATE_START>>\n")
			fmt.Printf("System: %s\n", host)
			fmt.Printf("Observation: %s = %s\n", metricName, value)
			fmt.Printf("Severity: %s\n", severity)
			fmt.Printf("<<TEMPLATE_END>>\n\n")
		}
	}
}
EOF

    cd /tmp
    go build -ldflags="-s -w" -o /app/legacy_transformer legacy.go
    rm legacy.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
