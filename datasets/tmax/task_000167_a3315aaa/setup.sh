#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg expect
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create mock_router
    cat << 'EOF' > /app/mock_router
#!/bin/bash
echo -n "Username: "
read user
echo -n "Password: "
read -s pass
echo
echo -n "Router# "
read cmd
if [ "$cmd" = "show interface status" ]; then
    echo "GigabitEthernet0/0/0  up      up"
fi
echo -n "Router# "
read cmd
EOF
    chmod +x /app/mock_router

    # Create legacy_analyzer_oracle in Go
    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	if scanner.Scan() {
		line := scanner.Text()
		line = strings.ToUpper(line)

		re := regexp.MustCompile(`\b(?:\d{1,3}\.){3}\d{1,3}\b`)
		ips := re.FindAllString(line, -1)

		line = strings.ReplaceAll(line, " ", "-")

		if len(ips) > 0 {
			line = line + "-" + strings.Join(ips, "-")
		}
		fmt.Println(line)
	}
}
EOF
    go build -o /app/legacy_analyzer_oracle /app/oracle.go
    rm /app/oracle.go

    # Generate router_led.mp4 efficiently
    ffmpeg -f lavfi -i color=c=green:s=10x10:d=0.1 -c:v libx264 -y /tmp/g.mp4
    ffmpeg -f lavfi -i color=c=red:s=10x10:d=0.1 -c:v libx264 -y /tmp/r.mp4

    cat << 'EOF' > /tmp/list.txt
file '/tmp/g.mp4'
file '/tmp/r.mp4'
file '/tmp/g.mp4'
file '/tmp/r.mp4'
file '/tmp/g.mp4'
file '/tmp/r.mp4'
file '/tmp/g.mp4'
file '/tmp/r.mp4'
file '/tmp/g.mp4'
file '/tmp/r.mp4'
file '/tmp/g.mp4'
file '/tmp/r.mp4'
file '/tmp/g.mp4'
file '/tmp/r.mp4'
file '/tmp/g.mp4'
EOF

    ffmpeg -f concat -safe 0 -i /tmp/list.txt -c copy -y /app/router_led.mp4
    rm /tmp/g.mp4 /tmp/r.mp4 /tmp/list.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
