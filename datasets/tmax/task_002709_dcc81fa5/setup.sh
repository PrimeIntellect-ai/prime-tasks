#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libssl-dev gcc make gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Generate the reference binary file
    dd if=/dev/urandom of=/home/user/known_good.bin bs=1024 count=4 status=none

    # Calculate hashes for the setup script
    GOOD_HASH=$(sha256sum /home/user/known_good.bin | gawk '{print $1}')
    BAD_HASH_1=$(echo -n "malware1" | sha256sum | gawk '{print $1}')
    BAD_HASH_2=$(echo -n "malware2" | sha256sum | gawk '{print $1}')

    # Generate revoked certs
    REVOKED_1="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    REVOKED_2="1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    REVOKED_3="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    VALID_CERT="fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321"

    echo "$REVOKED_1" > /home/user/revoked_certs.txt
    echo "$REVOKED_2" >> /home/user/revoked_certs.txt
    echo "$REVOKED_3" >> /home/user/revoked_certs.txt

    # Create the security events log
    cat <<EOF > /home/user/sec_events.log
192.168.1.10|$VALID_CERT|default-src 'self'; script-src 'none'|$GOOD_HASH
192.168.1.11|$REVOKED_1|default-src 'none'|$GOOD_HASH
192.168.1.12|$VALID_CERT|script-src 'unsafe-inline'|$BAD_HASH_1
10.0.0.5|$REVOKED_2|script-src 'unsafe-inline'|$BAD_HASH_1
10.0.0.6|$REVOKED_1|default-src 'self'|$BAD_HASH_2
10.0.0.7|$REVOKED_3|default-src *; img-src 'self'|$BAD_HASH_2
172.16.0.4|$REVOKED_2|default-src 'self'|$GOOD_HASH
172.16.0.8|$REVOKED_1|script-src 'none'|$BAD_HASH_1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
