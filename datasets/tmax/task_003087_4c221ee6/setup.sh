#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/evidence/bin

    printf "good ls" > /home/user/evidence/bin/ls
    printf "good cat" > /home/user/evidence/bin/cat
    printf "good ps" > /home/user/evidence/bin/ps
    printf "malicious sysstat" > /home/user/evidence/bin/sysstat

    cat << 'EOF' > /home/user/evidence/checksums.md5
2a6119106093fb1d0b3b4aa5826fdb1b  ls
8f9ba3c0eeb5de8ff89aef7a96aeb328  cat
01c5eb02dd5e2deca3da2c5625bfdf93  ps
d41d8cd98f00b204e9800998ecf8427e  sysstat
EOF

    cat << 'EOF' > /home/user/evidence/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0000] "GET /index.html HTTP/1.1" 200 1024 "-" "Mozilla/5.0"
10.0.0.5 - - [10/Oct/2023:13:58:12 -0000] "GET /exfiltrate?data=auth HTTP/1.1" 200 42 "Cookie: session_id=A9f8B1c03dE; user=admin" "curl/7.68.0"
192.168.1.12 - - [10/Oct/2023:14:01:02 -0000] "POST /login HTTP/1.1" 401 512 "-" "Mozilla/5.0"
EOF

    cat << 'EOF' > /home/user/evidence/lock.go
package main
import (
    "crypto/md5"
    "fmt"
)
func main() {
    // Example logic used by attacker
    pin := "0000" // 4-digit PIN
    salt := "SALT_FORENSICS"
    hash := md5.Sum([]byte(salt + pin))
    fmt.Printf("%x\n", hash)
}
EOF

    printf "e28f328a9eb9c882d2bb2e1cb465de2d" > /home/user/evidence/secret.hash

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
