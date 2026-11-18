#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go supervisor
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > generator.py
import socket
import time
import random

def run():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 9001))
    server.listen(1)
    print("Generator listening on 9001")

    while True:
        conn, addr = server.accept()
        print("Accepted connection from", addr)
        try:
            while True:
                # Generate a batch of logs
                logs = ""
                for _ in range(1000):
                    logs += f"[1234567890] 192.168.1.1 10.0.0.1 TCP {random.randint(100, 1000)}\n"
                conn.sendall(logs.encode())
        except Exception as e:
            print("Connection closed", e)
            conn.close()

if __name__ == '__main__':
    run()
EOF

    cat << 'EOF' > aggregator.py
import socket
import time
import json
import threading

stats = {
    "total_processed": 0,
    "uptime_seconds": 0
}
start_time = time.time()

def run():
    time.sleep(3) # artificial delay
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 9002))
    server.listen(5)
    print("Aggregator listening on 9002")

    while True:
        conn, addr = server.accept()
        threading.Thread(target=handle_client, args=(conn,)).start()

def handle_client(conn):
    try:
        while True:
            data = conn.recv(1024).decode()
            if not data:
                break
            if "STATS" in data:
                stats["uptime_seconds"] = time.time() - start_time
                conn.sendall(json.dumps(stats).encode())
            else:
                # assume it's a number to add
                try:
                    for line in data.split():
                        if line.isdigit():
                            stats["total_processed"] += int(line)
                except:
                    pass
    except Exception as e:
        pass
    finally:
        conn.close()

if __name__ == '__main__':
    run()
EOF

    cat << 'EOF' > processor.go
package main

import (
	"bufio"
	"fmt"
	"log"
	"net"
	"regexp"
)

func main() {
	// Connect to aggregator
	aggConn, err := net.Dial("tcp", "127.0.0.1:9002")
	if err != nil {
		log.Fatal("Failed to connect to aggregator:", err)
	}
	defer aggConn.Close()

	// Connect to generator
	genConn, err := net.Dial("tcp", "127.0.0.1:9001")
	if err != nil {
		log.Fatal("Failed to connect to generator:", err)
	}
	defer genConn.Close()

	scanner := bufio.NewScanner(genConn)
	count := 0
	for scanner.Scan() {
		line := scanner.Text()

		// Inefficient regex compilation inside the loop
		re := regexp.MustCompile(`\[.*?\]\s+\S+\s+\S+\s+(TCP)\s+(\d+)`)
		matches := re.FindStringSubmatch(line)

		if len(matches) > 0 {
			count++
			if count%10000 == 0 {
				fmt.Fprintf(aggConn, "%d\n", 10000)
			}
		}
	}
}
EOF

    cat << 'EOF' > supervisord.conf
[supervisord]
nodaemon=true
logfile=/tmp/supervisord.log
pidfile=/tmp/supervisord.pid

[program:generator]
command=python3 /home/user/app/generator.py
autorestart=true

[program:aggregator]
command=python3 /home/user/app/aggregator.py
autorestart=true
priority=999

[program:processor]
command=/home/user/app/processor_bin
autorestart=false
priority=1

[unix_http_server]
file=/tmp/supervisor.sock

[supervisorctl]
serverurl=unix:///tmp/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
EOF

    cat << 'EOF' > verifier.py
import time, socket, json, subprocess

subprocess.run(["/home/user/app/deploy.sh"], check=True)
time.sleep(5)

s = socket.socket()
s.connect(("127.0.0.1", 9002))
s.send(b"STATS\n")
data = s.recv(1024).decode()
stats = json.loads(data)

throughput = stats["total_processed"] / stats["uptime_seconds"]

print(f"Throughput: {throughput}")
if throughput >= 50000:
    exit(0)
else:
    exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
