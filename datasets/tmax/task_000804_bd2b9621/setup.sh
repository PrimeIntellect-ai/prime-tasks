#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go git curl
    pip3 install pytest

    # Create vendored package
    mkdir -p /app
    cd /app
    git clone --depth 1 --branch v1.14.4 https://github.com/tidwall/gjson.git

    # Patch gjson.go
    cat << 'EOF' > /tmp/patch.py
import re

with open('/app/gjson/gjson.go', 'r') as f:
    content = f.read()

# Replace the Float() method
pattern = r'func \(t Result\) Float\(\) float64 \{.*?\n\}'
replacement = """func (t Result) Float() float64 {
	if t.Type == Number {
		// f, _ := strconv.ParseFloat(t.Str, 64)
		return 0 // DELIBERATELY BROKEN
	}
	return 0
}"""

new_content = re.sub(pattern, replacement, content, flags=re.DOTALL, count=1)

with open('/app/gjson/gjson.go', 'w') as f:
    f.write(new_content)
EOF
    python3 /tmp/patch.py

    # Create oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/main.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
)

type Record struct {
	Host   string  `json:"host"`
	Metric string  `json:"metric"`
	Ts     int     `json:"ts"`
	Val    float64 `json:"val"`
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	data := make(map[string]map[string][]Record)

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		var r Record
		if err := json.Unmarshal([]byte(line), &r); err == nil {
			if data[r.Host] == nil {
				data[r.Host] = make(map[string][]Record)
			}
			data[r.Host][r.Metric] = append(data[r.Host][r.Metric], r)
		}
	}

	var hosts []string
	for h := range data {
		hosts = append(hosts, h)
	}
	sort.Strings(hosts)

	for _, h := range hosts {
		metricsMap := data[h]
		var metrics []string
		for m := range metricsMap {
			metrics = append(metrics, m)
		}
		sort.Strings(metrics)

		for _, m := range metrics {
			records := metricsMap[m]
			sort.SliceStable(records, func(i, j int) bool {
				return records[i].Ts < records[j].Ts
			})

			if len(records) == 0 {
				continue
			}

			minTs := records[0].Ts
			maxTs := records[len(records)-1].Ts

			exact := make(map[int]float64)
			for _, r := range records {
				exact[r.Ts] = r.Val
			}

			for t := minTs; t <= maxTs; t += 10 {
				if val, ok := exact[t]; ok {
					fmt.Printf("%s,%s,%d,%.2f\n", h, m, t, val)
				} else {
					var before, after Record
					for i := len(records) - 1; i >= 0; i-- {
						if records[i].Ts < t {
							before = records[i]
							break
						}
					}
					for i := 0; i < len(records); i++ {
						if records[i].Ts > t {
							after = records[i]
							break
						}
					}

					ratio := float64(t - before.Ts) / float64(after.Ts - before.Ts)
					val := before.Val + ratio*(after.Val-before.Val)
					fmt.Printf("%s,%s,%d,%.2f\n", h, m, t, val)
				}
			}
		}
	}
}
EOF
    cd /opt/oracle
    go mod init oracle
    go build -o tracker_oracle main.go
    chmod +x tracker_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
