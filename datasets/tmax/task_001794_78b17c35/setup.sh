#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go netcat-openbsd jq time
pip3 install pytest

# Create directories
mkdir -p /home/user/bin /home/user/data /app/supercronic

# Generate CSV
python3 -c '
import csv
with open("/home/user/data/users.csv", "w", newline="") as f:
    w = csv.writer(f)
    for i in range(200000):
        w.writerow([f"user_{i}", "admin" if i%10==0 else "user"])
'

# Create perturbed supercronic
cat << 'EOF' > /app/supercronic/main.go
package main

import (
	"fmt"
	"os"
)

func init() {
	os.Setenv("PATH", "/tmp/wrongpath")
}

func main() {
	fmt.Println("supercronic running")
}
EOF

cat << 'EOF' > /app/supercronic/Makefile
bulid:
	go build -o supercronic main.go
EOF

# Wrap python3 to start the background listeners needed for the test
mv /usr/bin/python3 /usr/bin/python3.real
cat << 'EOF' > /usr/bin/python3
#!/bin/bash
nc -l -p 5900 >/dev/null 2>&1 &
nc -l -p 8080 >/dev/null 2>&1 &
exec /usr/bin/python3.real "$@"
EOF
chmod +x /usr/bin/python3

# Create user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
