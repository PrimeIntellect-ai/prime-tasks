#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bash grep diffutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config.txt
root
admin
superuser
EOF

    cat << 'EOF' > /home/user/validator.sh
#!/bin/bash
INPUT=$(cat)
if grep -qFx "$INPUT" /home/user/config.txt; then
    exit 1
else
    exit 0
fi
EOF

    chmod +x /home/user/validator.sh
    chmod -R 777 /home/user
