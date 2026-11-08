#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the dummy auth_tool
    cat << 'EOF' > /home/user/auth_tool
#!/bin/bash
if [ -n "$1" ]; then
    # Insecure mode
    sleep 0.1
elif [ -n "$SECRET_TOKEN" ]; then
    # Secure mode
    sleep 0.1
fi
EOF
    chmod +x /home/user/auth_tool

    # Generate a secret token
    SECRET="tk_live_8f92bd39a44c7091e7b9"

    # Create the vulnerable loop script
    cat << EOF > /home/user/vuln_loop.sh
#!/bin/bash
while true; do
    /home/user/auth_tool $SECRET
    sleep 2
done
EOF
    chmod +x /home/user/vuln_loop.sh

    chmod -R 777 /home/user
