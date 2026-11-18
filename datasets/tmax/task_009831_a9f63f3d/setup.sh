#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/math_eval

cat << 'EOF' > /tmp/verify.sh
#!/bin/bash

# Check if artifact exists
if [ ! -f /home/user/artifact.tar.gz ]; then
    echo "Artifact not found."
    exit 1
fi

# Extract and verify
mkdir -p /tmp/verify_extract
tar -xzf /home/user/artifact.tar.gz -C /tmp/verify_extract

if [ ! -f /tmp/verify_extract/calc_tool ]; then
    echo "calc_tool binary not found in tarball."
    exit 1
fi

if [ ! -f /tmp/verify_extract/test_output.txt ]; then
    echo "test_output.txt not found in tarball."
    exit 1
fi

# Check expected outputs
EXPECTED=$(cat << 'EOM'
6.0000
333.3333
40.0000
39.7500
EOM
)

ACTUAL=$(cat /tmp/verify_extract/test_output.txt | tr -d '\r')

if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Output mismatch."
    echo "Expected:"
    echo "$EXPECTED"
    echo "Actual:"
    echo "$ACTUAL"
    exit 1
fi

echo "Verification passed."
exit 0
EOF

    chmod +x /tmp/verify.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
