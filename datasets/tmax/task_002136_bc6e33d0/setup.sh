#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make netcat-openbsd
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/port-monitor-1.0

    # Create Makefile
    cat << 'EOF' > /app/port-monitor-1.0/Makefile
PREFIX=/usr/local

install:
	mkdir -p $(PREFIX)/bin
	cp port-monitor.sh $(PREFIX)/bin/port-monitor.sh
	chmod +x $(PREFIX)/bin/port-monitor.sh
EOF

    # Create port-monitor.sh
    cat << 'EOF' > /app/port-monitor-1.0/port-monitor.sh
#!/bin/bash
PORTS_FILE=$1
LOG_FILE=$2
> "$LOG_FILE"
while read port; do
    nc -z -w 1 127.0.0.1 $port 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Port $port is DOWN" >> "$LOG_FILE"
    fi
done < "$PORTS_FILE"
EOF

    chmod +x /app/port-monitor-1.0/port-monitor.sh

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
