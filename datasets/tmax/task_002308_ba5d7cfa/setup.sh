#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/automator

    cat << 'EOF' > /home/user/qemu_serial_mock.sh
#!/bin/bash
echo "Timezone:"
read tz
echo "Locale:"
read loc
echo "IP:"
read ip
echo "Gateway:"
read gw
echo -e "TZ=$tz\nLOCALE=$loc\nIP=$ip\nGW=$gw" > /home/user/vm_state.conf
echo "Done."
EOF
    chmod +x /home/user/qemu_serial_mock.sh

    cat << 'EOF' > /home/user/deploy_spec.txt
Europe/Berlin
de_DE.UTF-8
192.168.150.22/24
192.168.150.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
