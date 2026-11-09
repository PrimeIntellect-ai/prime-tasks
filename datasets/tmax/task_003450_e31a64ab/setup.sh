#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    cat << 'EOF' > /home/user/bin/mock_qemu
#!/bin/bash
echo "Initializing QEMU virtual machine..."
sleep 0.5
echo "Loading bootloader..."
echo -n "Press 'c' to continue boot... "
read -t 2 input
if [ "$input" = "c" ]; then
    echo ""
    echo "[ OK ] Booting kernel..."
    sleep 0.5
    echo "BOOT SUCCESS"
    exit 0
else
    echo ""
    echo "[ FAIL ] Timeout or incorrect input."
    echo "KERNEL PANIC - not syncing"
    exit 1
fi
EOF
    chmod +x /home/user/bin/mock_qemu

    chmod -R 777 /home/user
