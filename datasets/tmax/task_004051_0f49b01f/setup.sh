#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/suspect_dir/subdir

    # 1. Normal file
    echo "Just a normal config file." > /home/user/suspect_dir/config.txt

    # 2. World-writable file
    echo "echo 'backdoor'" > /home/user/suspect_dir/backdoor_script.sh

    # 3. SUID file containing an evidence flag
    echo "Binary blob with SUID... EVIDENCE_FLAG_Q1W2E3R4T5Y6U7I8 hidden inside." > /home/user/suspect_dir/suid_dropper.bin

    # 4. Malicious file matching an IOC, containing an evidence flag
    echo "Malicious payload... EVIDENCE_FLAG_Z9Y8X7W6V5U4T3S2 embedded here." > /home/user/suspect_dir/subdir/payload.so

    # 5. Generate IOC hashes file
    MALICIOUS_HASH=$(sha256sum /home/user/suspect_dir/subdir/payload.so | awk '{print $1}')
    DUMMY_HASH="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    echo "$MALICIOUS_HASH" > /home/user/ioc_hashes.txt
    echo "$DUMMY_HASH" >> /home/user/ioc_hashes.txt

    # Set base permissions for the home directory
    chmod -R 777 /home/user

    # Re-apply specific file permissions required by the task and tests
    chmod 644 /home/user/suspect_dir/config.txt
    chmod 777 /home/user/suspect_dir/backdoor_script.sh
    chmod 4755 /home/user/suspect_dir/suid_dropper.bin
    chmod 755 /home/user/suspect_dir/subdir/payload.so
