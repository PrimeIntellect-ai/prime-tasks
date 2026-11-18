#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git expect
    pip3 install pytest

    git config --system user.name "Test User"
    git config --system user.email "test@example.com"
    git config --system init.defaultBranch master

    mkdir -p /home/user
    cd /home/user
    git init --bare alerts_repo.git
    git clone /home/user/alerts_repo.git workspace
    cd workspace
    git commit --allow-empty -m "Initial commit"
    git push origin master

    cat << 'EOF' > /home/user/workspace/make_alert.sh
#!/bin/bash
cd /home/user/workspace
read -p "Enter alert filename: " filename
read -p "Enter severity: " severity
read -p "Enter message: " message
echo "$severity: $message" > "$filename"
git add "$filename"
git commit -m "Add alert $filename"
git push origin master
EOF

    chmod +x /home/user/workspace/make_alert.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
