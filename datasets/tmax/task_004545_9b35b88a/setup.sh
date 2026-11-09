#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/bloated_data/dirA/dirB/dirC
    mkdir -p /home/user/bloated_data/dirX/dirY

    # Create unique files
    echo "Project Alpha Data" > /home/user/bloated_data/alpha.txt
    echo "Financial Report 2023" > /home/user/bloated_data/dirA/finance.csv
    echo "System configuration logs" > /home/user/bloated_data/dirA/dirB/sys.log
    echo "Important user data" > /home/user/bloated_data/dirX/users.json

    # Create duplicate files
    echo "Project Alpha Data" > /home/user/bloated_data/dirA/dirB/dirC/alpha_backup.txt
    echo "Financial Report 2023" > /home/user/bloated_data/dirX/dirY/finance_copy.csv
    echo "System configuration logs" > /home/user/bloated_data/sys_old.log

    # Create symlink loops
    ln -s /home/user/bloated_data/dirA /home/user/bloated_data/dirA/dirB/dirC/loop_to_A
    ln -s /home/user/bloated_data/ /home/user/bloated_data/dirX/loop_to_root

    # Create config
    cat << 'EOF' > /home/user/config.json
{
  "source_dir": "/home/user/bloated_data",
  "dest_dir": "/home/user/cleaned_data",
  "manifest_path": "/home/user/manifest.json"
}
EOF

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chown -R user:user /home/user/bloated_data
    chown user:user /home/user/config.json
    chmod -R 777 /home/user
