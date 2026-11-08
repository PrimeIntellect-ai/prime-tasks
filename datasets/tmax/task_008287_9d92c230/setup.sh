#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/build_stats.csv
run_id,avg_packet_size,max_packet_size,status
101,150,420,passed
102,152,780,passed
103,160,512,timeout
104,149,300,passed
105,170,512,timeout
106,155,600,passed
107,158,512,timeout
EOF

    cat << 'EOF' > /home/user/goroutine_dump.txt
goroutine 1 [semacquire]:
sync.runtime_SemacquireMutex(0xc0000140c0, 0x1)
	/usr/local/go/src/runtime/sema.go:71 +0x47
sync.(*Mutex).lockSlow(0xc0000140c0)
	/usr/local/go/src/sync/mutex.go:138 +0x105
sync.(*Mutex).Lock(0xc0000140c0)
	/usr/local/go/src/sync/mutex.go:81 +0x4d
main.processPacket(0x200, {0x4a, 0xc0000160a0})
	/home/user/app/main.go:35 +0x8a

goroutine 18 [runnable]:
main.processPacket(...)
	/home/user/app/main.go:28
	last_payload = "CRITICAL_ERR_OOM_9912"
	packet_size = 512
EOF

    cat << 'EOF' > /home/user/app/traffic.pcap
420,NORMAL_DATA
300,NORMAL_DATA
512,CRITICAL_ERR_OOM_9912
600,NORMAL_DATA
780,NORMAL_DATA
EOF

    cat << 'EOF' > /home/user/app/main.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
)

var (
	mu sync.Mutex
	processedCount int
)

func processPacket(size int, payload string, wg *sync.WaitGroup) {
	defer wg.Done()
	mu.Lock()

	if size == 512 {
		// BUG: Returns without unlocking!
		return
	}

	processedCount++
	mu.Unlock()
}

func main() {
	file, err := os.Open("traffic.pcap")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var wg sync.WaitGroup
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		parts := strings.Split(scanner.Text(), ",")
		if len(parts) == 2 {
			size, _ := strconv.Atoi(parts[0])
			wg.Add(1)
			go processPacket(size, parts[1], &wg)
		}
	}
	wg.Wait()
	fmt.Printf("Success! Processed %d normal packets.\n", processedCount)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
