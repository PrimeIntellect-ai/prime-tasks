#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest pandas

    mkdir -p /app/go-humanize

    cat << 'EOF' > /app/go-humanize/go.mod
module github.com/dustin/go-humanize

go 1.18
EOF

    cat << 'EOF' > /app/go-humanize/times.go
package humanize
import "time"
func Time(t time.Time) string {
    // deliberate syntax error here (missing quote)
    return "just now
}
EOF

    mkdir -p /home/user/data /home/user/processed /home/user/server

    cat << 'EOF' > /home/user/data/loc_events.csv
timestamp,event_id,lang_code,raw_text,translated_text
2023-10-01T10:00:00Z,EVT-001,en,Hello,Hello
2023-10-01T10:00:00Z,EVT-001,es,Hello,Hola
2023-10-01T10:00:00Z,EVT-001,fr,Hello,Bonjour
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
