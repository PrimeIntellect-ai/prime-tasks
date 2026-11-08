#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest PyJWT

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs
    echo "master-secret-key-998877" > /home/user/master.key

    cat << 'EOF' > /home/user/configs/alpha.json
{
    "service": "alpha",
    "port": 8080,
    "token": "old-leaked-token-alpha"
}
EOF

    cat << 'EOF' > /home/user/configs/beta.json
{
    "service": "beta",
    "port": 8081,
    "token": "old-leaked-token-beta"
}
EOF

    cat << 'EOF' > /home/user/configs/gamma.json
{
    "service": "gamma",
    "port": 8082,
    "token": "valid-token-gamma"
}
EOF

    sha256sum /home/user/configs/*.json > /home/user/config_hashes.txt

    # Tamper with beta's configuration AFTER hashing
    cat << 'EOF' > /home/user/configs/beta.json
{
    "service": "beta",
    "port": 8081,
    "token": "old-leaked-token-beta",
    "malicious_injection": true
}
EOF

    # Create the security log
    cat << 'EOF' > /home/user/security.log
2023-10-01 10:00:00 [INFO] Service gamma started successfully.
2023-10-01 10:05:22 [LEAK_DETECTED] Service alpha token exposed in public repository.
2023-10-01 10:15:00 [WARN] High CPU usage on database node.
2023-10-01 10:22:11 [LEAK_DETECTED] Service beta token found in pastebin dump.
2023-10-01 10:30:00 [INFO] Scheduled maintenance completed.
EOF

    chmod -R 777 /home/user
