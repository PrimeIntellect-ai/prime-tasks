#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/input
    cat << 'EOF' > /home/user/input/events.csv
timestamp,event_id,severity,message
2023-11-01T08:15:30Z,EVT-001,INFO,"Service started successfully"
2023-11-01T08:15:30Z,EVT-001,INFO,"Service started successfully"
2023-11-01T08:45:12Z,EVT-002,WARN,"Memory usage high
Consider upgrading instance"
2023-11-01T08:50:00Z,EVT-003,INFO,"Heartbeat normal"
2023-11-01T09:05:00Z,EVT-004,ERROR,"Database connection lost
Retrying in 5 seconds..."
2023-11-01T09:10:00Z,EVT-005,ERROR,"Failed to reconnect to database"
2023-11-01T09:15:00Z,EVT-006,INFO,"User logged in"
EOF

    cat << 'EOF' > /home/user/process.go
package main
import (
    "bufio"
    "fmt"
    "os"
    "strings"
)
func main() {
    file, _ := os.Open("/home/user/input/events.csv")
    defer file.Close()
    scanner := bufio.NewScanner(file)
    for scanner.Scan() {
        parts := strings.Split(scanner.Text(), ",")
        fmt.Println(parts[0]) // buggy
    }
}
EOF

    chown -R user:user /home/user/input
    chown user:user /home/user/process.go
    chmod -R 777 /home/user
