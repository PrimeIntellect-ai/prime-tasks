#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generator.sh
#!/bin/bash
for i in {1..125}; do
    echo "Log entry $i: $(date -d "@$((1600000000 + i))" -u +"%Y-%m-%dT%H:%M:%SZ") - DATA BLOCK $i"
done
EOF
    chmod +x /home/user/generator.sh

    chmod -R 777 /home/user
