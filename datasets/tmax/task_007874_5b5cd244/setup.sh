#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/worker.sh
#!/bin/bash
# Dummy worker that just consumes some CPU user/sys time
while true; do
    echo "working" > /dev/null
done
EOF
    chmod +x /home/user/worker.sh

    chmod -R 777 /home/user
