#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_mounts.sh
#!/bin/bash
echo "--- User-Space Mount Configurator ---"
read -p "Enter device path: " dev_path
read -p "Enter mount point: " mount_point
read -p "Enter filesystem type: " fs_type
read -p "Enter mount options: " mount_opts

echo "$dev_path $mount_point $fs_type $mount_opts 0 0" > /home/user/my_fstab.conf
echo "Configuration saved to /home/user/my_fstab.conf"
EOF

    chmod +x /home/user/setup_mounts.sh

    chmod -R 777 /home/user
