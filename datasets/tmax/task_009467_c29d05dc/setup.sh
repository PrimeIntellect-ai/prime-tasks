#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget procps
    pip3 install pytest

    mkdir -p /tmp/remote_data
    cat << 'EOF' > /tmp/remote_data/log1.json
[
  {"timestamp": "2023-10-01T08:15:00Z", "value": 12.5},
  {"timestamp": "2023-10-01T08:45:00Z", "value": 18.2},
  {"timestamp": "2023-10-01T09:05:00Z", "value": 20.0}
]
EOF

    cat << 'EOF' > /tmp/remote_data/log2.json
[
  {"timestamp": "2023-10-01T08:55:00Z", "value": 19.1},
  {"timestamp": "2023-10-01T09:30:00Z", "value": 22.4},
  {"timestamp": "2023-10-01T10:15:00Z", "value": 15.0}
]
EOF

    cat << 'EOF' > /tmp/remote_data/log3.json
[
  {"timestamp": "2023-10-01T09:45:00Z", "value": 25.1},
  {"timestamp": "2023-10-01T10:45:00Z", "value": 17.8},
  {"timestamp": "2023-10-01T11:00:00Z", "value": 14.2}
]
EOF

    # Ensure the background server starts when a shell is opened
    cat << 'EOF' >> /etc/bash.bashrc
if ! pgrep -f "python3 -m http.server 8080" > /dev/null; then
    cd /tmp/remote_data
    python3 -m http.server 8080 > /dev/null 2>&1 &
    sleep 1
    cd - > /dev/null
fi
EOF

    cat << 'EOF' >> /etc/profile
if ! pgrep -f "python3 -m http.server 8080" > /dev/null; then
    cd /tmp/remote_data
    python3 -m http.server 8080 > /dev/null 2>&1 &
    sleep 1
    cd - > /dev/null
fi
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
