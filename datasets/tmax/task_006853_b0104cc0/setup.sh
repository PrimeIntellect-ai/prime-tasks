#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/.gitconfig
[user]
	email = user@example.com
	name = User
[init]
	defaultBranch = master
EOF

    chmod -R 777 /home/user
