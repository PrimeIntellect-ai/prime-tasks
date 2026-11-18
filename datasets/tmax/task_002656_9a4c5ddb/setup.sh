#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo sox nginx golang multimon-ng
    pip3 install pytest Levenshtein

    mkdir -p /home/user
    cat << 'EOF' > /home/user/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://unix:/tmp/wrong.sock;
        }
    }
}
EOF

    mkdir -p /app
    sox -V -r 8000 -n -c 1 /app/signal.wav synth 0.2 sine 852 sine 1336 \
        pad 0 0.1 synth 0.2 sine 770 sine 1477 pad 0 0.1 \
        synth 0.2 sine 852 sine 1209 pad 0 0.1 synth 0.2 sine 770 sine 1336 \
        pad 0 0.1 synth 0.2 sine 697 sine 1477 pad 0 0.1 \
        synth 0.2 sine 941 sine 1336 pad 0 0.1 synth 0.2 sine 852 sine 1477

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
