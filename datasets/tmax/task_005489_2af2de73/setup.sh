#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git expect
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.secrets
    echo "secret_token_8891ab" > /home/user/.secrets/deploy_token.txt

    cat << 'EOF' > /home/user/legacy_deploy.sh
#!/bin/bash
echo -n "Token: "
read input_token
REAL_TOKEN=$(cat /home/user/.secrets/deploy_token.txt)
if [ "$input_token" != "$REAL_TOKEN" ]; then
    echo "Auth failed."
    exit 1
fi
echo -n "Proceed with filesystem sync? (yes/no): "
read proceed
if [ "$proceed" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

mkdir -p /home/user/deploy_out
cp /home/user/deploy_workspace/* /home/user/deploy_out/ 2>/dev/null
echo "DEPLOY_SUCCESS" > /home/user/deploy_out/status.log
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod 600 /home/user/.secrets/deploy_token.txt
    chmod +x /home/user/legacy_deploy.sh
