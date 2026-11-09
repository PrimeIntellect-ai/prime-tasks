#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y expect g++ acl

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_deploy.sh
#!/bin/bash
echo -n "Enter migration token: "
read token
if [ "$token" = "CloudMigrate2024!" ]; then
    echo "Deployment successful."
    mkdir -p /home/user/deploy_dir
    echo "READY" > /home/user/deploy_dir/status.txt
else
    echo "Auth failed. Token rejected."
    exit 1
fi
EOF

    chmod +x /home/user/legacy_deploy.sh
    chown user:user /home/user/legacy_deploy.sh

    chmod -R 777 /home/user
