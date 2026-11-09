#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/qemu_configs

    cat << 'EOF' > /home/user/qemu_configs/vm_web.sh
#!/bin/bash
qemu-system-x86_64 -m 1024 -drive file=web.img,format=qcow2 -vnc 0.0.0.0:1,password=off -monitor stdio
EOF

    cat << 'EOF' > /home/user/qemu_configs/vm_db.sh
#!/bin/bash
qemu-system-x86_64 -m 2048 -drive file=db.img,format=qcow2 -vnc 127.0.0.1:2,password=on -daemonize
EOF

    cat << 'EOF' > /home/user/qemu_configs/vm_test.sh
#!/bin/bash
qemu-system-x86_64 -m 512 -drive file=test.img,format=qcow2 -vnc :3,password=off -net nic
EOF

    cat << 'EOF' > /home/user/qemu_configs/vm_safe.sh
#!/bin/bash
qemu-system-x86_64 -m 512 -drive file=safe.img,format=qcow2 -vnc :4,password=on
EOF

    chmod -R 777 /home/user

    chmod 777 /home/user/qemu_configs/vm_web.sh
    chmod 644 /home/user/qemu_configs/vm_db.sh
    chmod 777 /home/user/qemu_configs/vm_test.sh
    chmod 777 /home/user/qemu_configs/vm_safe.sh
