#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang espeak expect ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "The backup passphrase is solid snake"

    cat << 'EOF' > /tmp/oracle_parser.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	if scanner.Scan() {
		line := scanner.Text()
		re := regexp.MustCompile(`^\[(.*?)\] (.*?) - (.*?): (.*)$`)
		m := re.FindStringSubmatch(line)
		if len(m) == 5 {
			comp := m[3]
			if m[2] == "FATAL" {
				comp = strings.ToUpper(comp)
			}
			out := map[string]string{
				"timestamp": m[1],
				"level":     m[2],
				"component": comp,
				"message":   m[4],
			}
			b, _ := json.Marshal(out)
			fmt.Println(string(b))
		}
	}
}
EOF

    cd /tmp
    go build -o oracle_parser oracle_parser.go

    cat << 'EOF' > samples.txt
[2023-10-12T10:00:00Z] ERROR - db-primary: connection lost
[2023-10-12T10:01:00Z] FATAL - cache-node: out of memory
[2023-10-12T10:02:00Z] INFO - web-server: request processed
EOF

    tar -czf /app/data.tar.gz oracle_parser samples.txt

    # Also keep a hidden copy for the verifier if it expects it at /app/oracle_parser but the test forbids it initially
    mkdir -p /opt/oracle
    cp oracle_parser /opt/oracle/oracle_parser

    cat << 'EOF' > /app/secure_restore.sh
#!/bin/bash
read -p "Enter passphrase: " pass
if [ "$pass" == "solid snake" ]; then
    mkdir -p /home/user/restored_data
    tar -xzf /app/data.tar.gz -C /home/user/restored_data
    # The verifier expects /app/oracle_parser to exist, so we copy it here upon successful restore
    cp /home/user/restored_data/oracle_parser /app/oracle_parser
    echo "Restore successful."
else
    echo "Access denied."
    exit 1
fi
EOF
    chmod +x /app/secure_restore.sh

    rm -f /tmp/oracle_parser /tmp/oracle_parser.go /tmp/samples.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
