#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect rustc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/legacy_restore
#!/bin/bash
read -p "Enter restore password: " pass
if [ "$pass" != "backup2023" ]; then
    echo "Invalid password"
    exit 1
fi
read -p "Enter staging directory: " staging_dir
if [ -z "$staging_dir" ]; then
    echo "Staging directory cannot be empty"
    exit 1
fi
mkdir -p "$staging_dir"
echo "RESTORE_SUCCESS_99182" > "$staging_dir/restored_data.txt"
echo "Restore complete."
EOF
    chmod +x /home/user/legacy_restore

    mkdir -p /home/user/staging
    mkdir -p /home/user/prod

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
