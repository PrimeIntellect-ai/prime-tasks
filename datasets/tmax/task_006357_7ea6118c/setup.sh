#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/microservice.sh
#!/bin/bash
echo $$ > /home/user/service.pid
while true; do
    sleep 60
done
EOF

    chmod +x /home/user/microservice.sh

    chmod -R 777 /home/user
