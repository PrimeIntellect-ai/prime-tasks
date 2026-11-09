#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssl tar
    pip3 install pytest pexpect

    mkdir -p /home/user/bin /home/user/staging

    cat << 'EOF' > /home/user/bin/approve_release.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Error: Missing filename"
    exit 1
fi
echo -n "Approve deployment of $1? (yes/no): "
read answer
if [ "$answer" == "yes" ]; then
    echo "Approved."
    exit 0
else
    echo "Rejected."
    exit 1
fi
EOF
    chmod +x /home/user/bin/approve_release.sh

    mkdir -p /tmp/app-v1.0
    echo "Hello World!" > /tmp/app-v1.0/index.html
    tar -czf /home/user/staging/app-v1.0.tar.gz -C /tmp app-v1.0
    rm -rf /tmp/app-v1.0

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
