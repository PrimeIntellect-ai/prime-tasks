#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl
    pip3 install pytest pyyaml

    # Create the user first
    useradd -m -s /bin/bash user || true

    # Initialize bare repository
    mkdir -p /home/user/cluster-state.git
    cd /home/user/cluster-state.git
    git init --bare

    # Create the silent rejection pre-receive hook
    cat << 'EOF' > /home/user/cluster-state.git/hooks/pre-receive
#!/bin/bash
# Silently reject
exit 1
EOF
    chmod +x /home/user/cluster-state.git/hooks/pre-receive

    # Set up the workspace
    git clone /home/user/cluster-state.git /home/user/workspace
    cd /home/user/workspace
    git config user.name "Operator Admin"
    git config user.email "admin@local"
    echo "# Initial commit" > README.md
    git add README.md
    git commit -m "Initial commit"

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
