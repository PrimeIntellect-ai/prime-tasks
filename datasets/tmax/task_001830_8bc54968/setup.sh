#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git expect iproute2
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Global git config to allow ext transport
    git config --system protocol.ext.allow always

    # 1. Initialize bare repo
    mkdir -p /home/user/central.git
    git init --bare /home/user/central.git

    # 2. Create the custom wrapper that simulates the pin prompt
    cat << 'EOF' > /home/user/git-wrapper.sh
#!/bin/bash
read -p "Enter Deployment Pin: " pin
if [ "$pin" != "8821" ]; then
    echo "Invalid Pin"
    exit 1
fi
exec git "$@"
EOF
    chmod +x /home/user/git-wrapper.sh

    # 3. Create the workspace and local clone
    git clone /home/user/central.git /home/user/workspace
    cd /home/user/workspace
    git config user.name "Network Engineer"
    git config user.email "neteng@example.com"
    git commit --allow-empty -m "Initial commit"
    git push origin master

    # 4. Force the git wrapper for pushes in the workspace
    git config core.sshCommand "false"
    git remote set-url origin "ext::/home/user/git-wrapper.sh %G /home/user/central.git"

    chown -R user:user /home/user/central.git /home/user/workspace /home/user/git-wrapper.sh
    chmod -R 777 /home/user
