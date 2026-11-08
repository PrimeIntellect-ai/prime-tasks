#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/suspicious_dir

    cat << 'EOF' > /home/user/service.log
[2023-10-27 10:00:00] GET /api/v1/health?payload=ZWNobyAiaGVsbG8i HTTP/1.1
[2023-10-27 10:01:00] GET /api/v1/health?payload=d2dldCBodHRwOi8vMjAzLjAuMTEzLjQ1L2JhY2tkb29yLnNo HTTP/1.1
[2023-10-27 10:02:00] GET /api/v1/health?payload=bmNhdCAxOTguNTEuMTAwLjIyIDQ0NDQgLWUgL2Jpbi9iYXNo HTTP/1.1
[2023-10-27 10:03:00] GET /api/v1/health?payload=cGluZyA4LjguOC44 HTTP/1.1
[2023-10-27 10:04:00] GET /api/v1/health?payload=d2dldCBodHRwOi8vMTAuMTAuMTAuMTAvZHJvcC5iaW4= HTTP/1.1
[2023-10-27 10:05:00] GET /api/v1/health?payload=bmNhdCAxOTguNTEuMTAwLjIyIDU1NTU= HTTP/1.1
EOF

    chmod -R 777 /home/user

    # Set specific permissions for the test files after the recursive chmod
    touch /home/user/suspicious_dir/clean_file.txt
    chmod 644 /home/user/suspicious_dir/clean_file.txt

    touch /home/user/suspicious_dir/backdoor_bin
    chmod 4755 /home/user/suspicious_dir/backdoor_bin

    touch /home/user/suspicious_dir/config.json
    chmod 777 /home/user/suspicious_dir/config.json

    touch /home/user/suspicious_dir/script.sh
    chmod 755 /home/user/suspicious_dir/script.sh

    touch /home/user/suspicious_dir/suid_script
    chmod 4644 /home/user/suspicious_dir/suid_script
