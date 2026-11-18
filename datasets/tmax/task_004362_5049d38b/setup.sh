#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git gawk
pip3 install pytest pexpect

useradd -m -s /bin/bash user || true

# Configure git globally for all users
git config --system user.email "admin@example.com"
git config --system user.name "Admin"
git config --system init.defaultBranch master

mkdir -p /home/user/bin
mkdir -p /home/user/config_workspace

cat << 'EOF' > /home/user/bin/deploy_configs.py
#!/usr/bin/env python3
import os
import sys

def main():
    deploy_path = os.environ.get('MICRO_DEPLOY_PATH', '/tmp/default_deploy')

    # Force interactive prompt
    try:
        sys.stdout.write("Apply changes? [y/N]: ")
        sys.stdout.flush()
        response = sys.stdin.readline().strip().lower()
    except KeyboardInterrupt:
        sys.exit(1)

    if response == 'y':
        os.makedirs(deploy_path, exist_ok=True)
        with open(os.path.join(deploy_path, 'deploy_success.flag'), 'w') as f:
            f.write("DEPLOYED\n")
        print(f"Successfully deployed to {deploy_path}")
    else:
        print("Deployment aborted.")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
chmod +x /home/user/bin/deploy_configs.py

git init --bare /home/user/config_repo.git

cd /home/user/config_workspace
git init
git remote add origin /home/user/config_repo.git
touch README.md
git add README.md
git commit -m "Initial commit"
git push -u origin master

chown -R user:user /home/user
chmod -R 777 /home/user
