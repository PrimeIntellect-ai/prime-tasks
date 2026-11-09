#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the binary data file
    echo -e "Random binary header \x00\x01\x02\x03" > /home/user/data.bin
    echo "Connection attempt from 192.168.13.37 logged." >> /home/user/data.bin
    echo -e "\x04\x05\x06 End of data." >> /home/user/data.bin

    # Setup git repo
    mkdir -p /home/user/data_pipeline
    cd /home/user/data_pipeline
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Commit 1 (Good - Tagged v1.0)
    cat << 'EOF' > build.sh
#!/bin/bash
if [ -z "$DATA_FILE" ]; then
    echo "Error: DATA_FILE environment variable is not set."
    exit 1
fi
echo "Processing $DATA_FILE..."
exit 0
EOF
    chmod +x build.sh
    git add build.sh
    git commit -m "Initial commit, build script added"
    git tag v1.0

    # Commit 2 (Good)
    echo "Adding feature A" > feature_a.txt
    git add feature_a.txt
    git commit -m "Add feature A"

    # Commit 3 (Bad - Introduces the regression)
    cat << 'EOF' > build.sh
#!/bin/bash
if [ -z "$DATA_FILE" ]; then
    echo "Error: DATA_FILE environment variable is not set."
    exit 1
fi
echo "Processing $DATA_FILE..."
# Faulty security check introduced here
if strings "$DATA_FILE" | grep -q "192.168.13.37"; then
    echo "Build failed: Suspicious IP detected in data file!"
    exit 1
fi
exit 0
EOF
    chmod +x build.sh
    git add build.sh
    git commit -m "Update build script with security check"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Commit 4 (Bad)
    echo "Adding feature B" > feature_b.txt
    git add feature_b.txt
    git commit -m "Add feature B"

    # Commit 5 (Bad)
    echo "Adding feature C" > feature_c.txt
    git add feature_c.txt
    git commit -m "Add feature C"

    # Store expected answers
    echo -n "$BAD_COMMIT" > /tmp/expected_bad_commit.txt

    chmod -R 777 /home/user
