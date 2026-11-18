#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/uptime_calculator

    # Create the dataset (Timestamps 100 to 200, representing 101 minutes)
    > /home/user/uptime_calculator/pings.jsonl
    for i in $(seq 100 200); do
      if [ "$i" -ge 140 ] && [ "$i" -le 154 ]; then
        echo "{\"timestamp\": $i, \"up\": false}" >> /home/user/uptime_calculator/pings.jsonl
      else
        echo "{\"timestamp\": $i, \"up\": true}" >> /home/user/uptime_calculator/pings.jsonl
      fi
    done

    # Create the buggy Go file
    cat << 'EOF' > /home/user/uptime_calculator/main.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"strings"
)

type Ping struct {
	Timestamp int  `json:"timestamp"`
	Up        bool `json:"up"`
}

func main() {
	data, err := ioutil.ReadFile("pings.jsonl")
	if err != nil {
		panic(err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	var pings []Ping
	for _, line := range lines {
		if line == "" {
			continue
		}
		var p Ping
		json.Unmarshal([]byte(line), &p)
		pings = append(pings, p)
	}

	// Bug 1: Off-by-one causing panic
	longestDowntime := 0
	currentDowntime := 0
	for i := 0; i <= len(pings); i++ {
		if !pings[i].Up {
			currentDowntime++
		} else {
			if currentDowntime > longestDowntime {
				longestDowntime = currentDowntime
			}
			currentDowntime = 0
		}
	}
	if currentDowntime > longestDowntime {
		longestDowntime = currentDowntime
	}

	// Bug 2: Query boundary condition (exclusive instead of inclusive)
	startTS := 100
	endTS := 200
	total := 0
	up := 0
	for _, p := range pings {
		if p.Timestamp >= startTS && p.Timestamp < endTS {
			total++
			if p.Up {
				up++
			}
		}
	}

	uptimePct := float64(up) / float64(total) * 100

	out := fmt.Sprintf(`{"longest_downtime_minutes": %d, "uptime_percentage": %.2f}`, longestDowntime, uptimePct)
	ioutil.WriteFile("/home/user/uptime_report.json", []byte(out), 0644)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
