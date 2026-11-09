#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go coreutils
    pip3 install pytest

    mkdir -p /home/user/edge/logs

    cat << 'EOF' > /home/user/edge/sensor.go
package main
import ("fmt"; "net")
func main() {
    conn, _ := net.Dial("udp", "127.0.0.1:8081")
    fmt.Fprintf(conn, "telemetry data")
}
EOF

    cat << 'EOF' > /home/user/edge/collector.go
package main
import ("fmt"; "net")
func main() {
    addr, _ := net.ResolveUDPAddr("udp", "127.0.0.1:9091")
    conn, _ := net.ListenUDP("udp", addr)
    buf := make([]byte, 1024)
    conn.ReadFromUDP(buf)
    fmt.Println(string(buf))
}
EOF

    dd if=/dev/zero of=/home/user/edge/logs/old_sys.log bs=1000 count=600
    touch -t 202301010000 /home/user/edge/logs/old_sys.log

    cat << 'EOF' > /home/user/edge/logs/recent_errors.log
2023-10-12T08:00:00Z [INFO] Started
2023-10-12T08:01:00Z [ERROR] Code 502: Bad Gateway
2023-10-12T08:02:00Z [ERROR] Code 404: Not Found
2023-10-12T08:03:00Z [ERROR] Code 502: Bad Gateway
2023-10-12T08:04:00Z [ERROR] Code 401: Unauthorized
2023-10-12T08:05:00Z [ERROR] Code 404: Not Found
2023-10-12T08:06:00Z [ERROR] Code 502: Bad Gateway
EOF
    touch -t 202310120806 /home/user/edge/logs/recent_errors.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
