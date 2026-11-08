#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx xxd coreutils
    pip3 install pytest

    mkdir -p /home/user/corpora/clean /home/user/corpora/evil /home/user/nginx/logs

    # Create clean payloads
    echo -n "0123456789abcdef0123456789abcde0" | xxd -r -p | base64 > /home/user/corpora/clean/1.txt
    echo -n "aabbccddeeff00112233445566778899abcdefabcdefabcdef1234567890abcd" | xxd -r -p | base64 > /home/user/corpora/clean/2.txt

    # Create evil payloads
    echo -n "4141414141414141414141414141414141414141414141414141414141414141" | xxd -r -p | base64 > /home/user/corpora/evil/1.txt
    echo -n "0000000000000000000000000000000011223344556677889900aabbccddeeff11223344556677889900aabbccddeeff" | xxd -r -p | base64 > /home/user/corpora/evil/2.txt

    # Default minimal Nginx config for agent to fix
    cat << 'EOF' > /home/user/nginx/nginx.conf
events {}
http {
    server {
        listen 80;
        location / {
            return 200 "OK\n";
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/corpora /home/user/nginx
    chmod -R 777 /home/user
