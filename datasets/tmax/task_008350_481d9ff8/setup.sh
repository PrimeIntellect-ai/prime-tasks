#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc tar
    pip3 install pytest

    mkdir -p /home/user/archive
    mkdir -p /home/user/restored_source

    cat << 'EOF' > /home/user/restored_source/qemu_vnc.log
INFO: Starting QEMU restore
VNC server running on 127.0.0.1:5901
WARN: CPU throttling active
VNC server running on 127.0.0.1:5902
ERROR: Failed to allocate memory
VNC server running on 127.0.0.1:5905
INFO: Shutdown complete
EOF

    dd if=/dev/zero of=/home/user/restored_source/disk.img bs=1M count=1

    cd /home/user/restored_source
    tar -czf /home/user/archive/sys_backup.tar.gz qemu_vnc.log disk.img
    cd /home/user
    rm -rf /home/user/restored_source

    useradd -m -s /bin/bash user || true

    # Create a script to start the background listener when a bash shell is invoked
    cat << 'EOF' > /etc/bash_env_script
python3 -c "import socket, time; s=socket.socket(); s.bind(('127.0.0.1', 5902)); s.listen(5); time.sleep(3600)" >/dev/null 2>&1 &
EOF
    chmod +x /etc/bash_env_script

    chmod -R 777 /home/user
