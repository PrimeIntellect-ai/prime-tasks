#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/main.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
)

type Input struct {
	ID        interface{} `json:"id"`
	Intervals [][]int     `json:"intervals"`
}

type Output struct {
	ID        interface{} `json:"id"`
	TotalSpan int         `json:"total_span"`
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		var in Input
		if err := json.Unmarshal([]byte(line), &in); err != nil {
			continue
		}

		span := 0
		if len(in.Intervals) > 0 {
			sort.Slice(in.Intervals, func(i, j int) bool {
				return in.Intervals[i][0] < in.Intervals[j][0]
			})

			merged := [][]int{in.Intervals[0]}
			for _, interval := range in.Intervals[1:] {
				last := merged[len(merged)-1]
				if interval[0] <= last[1] {
					if interval[1] > last[1] {
						merged[len(merged)-1][1] = interval[1]
					}
				} else {
					merged = append(merged, interval)
				}
			}

			for _, interval := range merged {
				span += interval[1] - interval[0]
			}
		}

		out := Output{ID: in.ID, TotalSpan: span}
		b, _ := json.Marshal(out)
		fmt.Println(string(b))
	}
}
EOF

    go build -o /app/legacy_processor /tmp/main.go
    strip /app/legacy_processor
    chmod +x /app/legacy_processor

    rm /tmp/main.go
    apt-get remove -y golang-go binutils
    apt-get autoremove -y

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/processor.py
import sys
import json
import threading
import queue

def process_worker(q, out_q):
    while True:
        item = q.get()
        # Deadlock: no sentinel check implemented

        try:
            data = json.loads(item)
            intervals = data.get("intervals", [])

            # Flawed interval merge logic
            span = 0
            for iv in intervals:
                span += iv[1] - iv[0]

            out_q.put(json.dumps({"id": data["id"], "total_span": span}))
        except Exception:
            pass
        q.task_done()

def main():
    q = queue.Queue()
    out_q = queue.Queue()

    # Start worker
    t = threading.Thread(target=process_worker, args=(q, out_q))
    t.daemon = True
    t.start()

    for line in sys.stdin:
        if line.strip():
            q.put(line)

    q.join()

    while not out_q.empty():
        print(out_q.get())

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
