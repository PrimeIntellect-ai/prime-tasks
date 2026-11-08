#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        socat \
        netcat \
        espeak \
        ffmpeg \
        curl

    pip3 install pytest SpeechRecognition

    mkdir -p /app
    espeak -w /app/voicemail.wav "Please create an account for user charlie with the secret passphrase ocean"

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /tmp/access.log;
    error_log /tmp/error.log;
    server {
        listen 8080;
        location / {
            proxy_pass http://unix:/tmp/wrong_path.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/backend.sh
#!/bin/bash
rm -f /tmp/backend.sock
socat UNIX-LISTEN:/tmp/backend.sock,fork,reuseaddr SYSTEM:"echo -e 'HTTP/1.1 200 OK\r\n\r\nNot Implemented'"
EOF
    chmod +x /home/user/backend.sh

    chmod -R 777 /home/user
    chmod -R 777 /app
