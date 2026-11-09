#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dropzone /home/user/curated /home/user/quarantine
    cd /home/user/dropzone

    # Pre-existing files
    # 1. Valid zip
    echo "dummy content" > dummy.txt
    zip "Initial Valid.zip" dummy.txt
    rm dummy.txt

    # 2. Corrupt zip
    echo "this is not a zip file" > "Bad Start.zip"

    cat << 'EOF' > /home/user/simulate_drops.sh
#!/bin/bash
cd /home/user/dropzone
sleep 1
# Drop valid tar.gz
mkdir -p test_dir
echo "hello" > test_dir/hello.txt
tar -czf "System Backup 1.tar.gz" test_dir
rm -rf test_dir

# Drop corrupt tar.gz
echo "corrupt data" > "Broken Archive.tar.gz"

sleep 2
# Drop another valid zip
echo "data" > data.bin
zip "Data package.zip" data.bin
rm data.bin

sleep 1
touch SHUTDOWN
EOF

    chmod +x /home/user/simulate_drops.sh
    chmod -R 777 /home/user
