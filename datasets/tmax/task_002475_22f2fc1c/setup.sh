#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq unzip zip
    pip3 install pytest

    mkdir -p /home/user/incoming /home/user/outgoing /home/user/artifact_manager
    cat << 'EOF' > /home/user/generate_test_data.sh
#!/bin/bash
mkdir -p /tmp/payload_src
# Create a 2.5 MB file (2500000 bytes)
dd if=/dev/urandom of=/tmp/payload_src/massive_data.bin bs=1000 count=2500 status=none
# Create a small metadata file (15 bytes)
echo "metadata=active" > /tmp/payload_src/info.txt
# Create a 1 MB file (exactly 1024000 bytes - should NOT be chunked based on strict greater than)
dd if=/dev/urandom of=/tmp/payload_src/edge_case.bin bs=1000 count=1024 status=none

cd /tmp/payload_src
tar -czf /tmp/payload.tar.gz *
cd - > /dev/null
EOF
    chmod +x /home/user/generate_test_data.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
