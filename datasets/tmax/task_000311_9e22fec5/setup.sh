#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/assets

    cat << 'EOF' > /home/user/project/calculate_threshold.sh
#!/bin/bash
sum=$(awk '{sum+=$1} END {print sum}' /home/user/project/weights.txt)
if [ "$sum" == "0.3" ]; then
    exit 0
else
    echo "Threshold failed: $sum != 0.3"
    exit 1
fi
EOF
    chmod +x /home/user/project/calculate_threshold.sh

    cat << 'EOF' > /home/user/project/weights.txt
0.1
0.2
EOF

    python3 -c "
with open('/home/user/project/core.dump', 'wb') as f:
    f.write(b'\x00\x01\x02\x03\x04\x05FATAL_ERROR: Corrupted asset found at /home/user/project/assets/config_data.bin\x00\x00\x1F\x7F')
with open('/home/user/project/assets/config_data.bin', 'wb') as f:
    f.write(b'VAL\x00ID_\x01ASSET\x02_123')
"

    cat << 'EOF' > /home/user/project/build.sh
#!/bin/bash
/home/user/project/calculate_threshold.sh || exit 1
asset_data=$(cat /home/user/project/assets/config_data.bin)
if [ "$asset_data" == "VALID_ASSET_123" ]; then
    echo "BUILD SUCCESSFUL"
else
    echo "ASSET CORRUPTED"
    exit 1
fi
EOF
    chmod +x /home/user/project/build.sh

    chmod -R 777 /home/user
