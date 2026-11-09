#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential expect systemd
    pip3 install pytest

    # Download and extract lz4 1.9.4
    mkdir -p /app
    cd /app
    wget https://github.com/lz4/lz4/archive/refs/tags/v1.9.4.tar.gz
    tar xzf v1.9.4.tar.gz
    rm v1.9.4.tar.gz

    # Apply perturbations
    cd lz4-1.9.4
    # Perturb Makefile
    sed -i 's/-O3/-O0/g' Makefile
    sed -i 's/-O3/-O0/g' programs/Makefile
    # Perturb lz4io.c buffer sizes
    sed -i '1i #define LZ4_IO_BUFFER_SIZE (1)' programs/lz4io.c
    sed -i 's/64 \* 1024/LZ4_IO_BUFFER_SIZE/g' programs/lz4io.c
    sed -i 's/256 \* 1024/LZ4_IO_BUFFER_SIZE/g' programs/lz4io.c

    # Create init_backup.sh
    cat << 'EOF' > /opt/init_backup.sh
#!/bin/bash
read -p "Initialize backup directory? (y/n): " answer
if [ "$answer" = "y" ]; then
    mkdir -p /backup
    echo "Initialized"
    exit 0
else
    echo "Aborted"
    exit 1
fi
EOF
    chmod +x /opt/init_backup.sh

    # Create systemd service
    cat << 'EOF' > /etc/systemd/system/log-archiver.service
[Unit]
Description=Log Archiver

[Service]
Type=oneshot
ExecStartPre=/opt/init_backup.sh
ExecStart=/usr/local/bin/lz4 -f /var/log/messages /backup/messages.lz4
EOF

    # Create dummy log file
    touch /var/log/messages
    echo "Sample log data" > /var/log/messages

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
