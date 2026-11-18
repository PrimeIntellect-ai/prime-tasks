#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/archives/
    echo "15" > /home/user/archiver.conf

    cat << 'EOF' > /home/user/generate_logs.sh
#!/bin/bash
for i in {1..42}; do
    echo "Log entry $i: Something happened at $(date)"
done
EOF
    chmod +x /home/user/generate_logs.sh

    chmod -R 777 /home/user
