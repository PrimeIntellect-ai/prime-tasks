#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat make
    pip3 install pytest

    mkdir -p /app/bash-backup-daemon-1.2.0

    cat << 'EOF' > /app/bash-backup-daemon-1.2.0/Makefile
PREFIX=/usr/local/bin
install:
	mkdir -p $(PREFIX)
	cp extract_stream.sh start_daemon.sh $(PREFIX)/
	chmod +x $(PREFIX)/*.sh
EOF

    cat << 'EOF' > /app/bash-backup-daemon-1.2.0/config.env.template
export DEST_DIR = /home/user/projects/extracted
export PORT=8080
EOF

    cat << 'EOF' > /app/bash-backup-daemon-1.2.0/extract_stream.sh
#!/bin/bash
source ./config.env.template
mkdir -p "$DEST_DIR"
cat - | tar -xzf - -C "$DEST_DIR"
echo "Extraction complete."
EOF

    cat << 'EOF' > /app/bash-backup-daemon-1.2.0/start_daemon.sh
#!/bin/bash
source ./config.env.template
echo "Listening on port $PORT..."
socat TCP4-LISTEN:$PORT,reuseaddr,fork EXEC:./extract_stream.sh
EOF

    chmod +x /app/bash-backup-daemon-1.2.0/*.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
