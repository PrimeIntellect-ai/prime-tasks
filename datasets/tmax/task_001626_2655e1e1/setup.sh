#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
    pip3 install pytest pyyaml flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/webapp
    mkdir -p /home/user/logs/raw
    mkdir -p /home/user/logs/processed
    mkdir -p /home/user/verifier/clean_corpus
    mkdir -p /home/user/verifier/evil_corpus

    cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/webapp/config.yaml
log_dir: /home/user/logs/processed/
EOF

    cat << 'EOF' > /home/user/app/restart_services.sh
#!/bin/bash
echo "Restarting services..."
nginx -s reload || nginx -c /home/user/app/nginx.conf
EOF
    chmod +x /home/user/app/restart_services.sh

    cat << 'EOF' > /home/user/verifier/clean_corpus/app.log
[2023-10-25 14:32:01] INFO Starting app
[2023-10-25 14:32:02] ERROR Something went wrong
Traceback (most recent call last):
  File "app.py", line 10, in <module>
EOF

    cat << 'EOF' > /home/user/verifier/evil_corpus/spam.log
[2023-10-25 14:32:01] INFO Starting app
[2023-10-25 14:32:02] ERROR [SPAM-MODULE] Generating spam
spam line 1
spam line 2
[2023-10-25 14:32:03] INFO App continues
EOF

    chmod -R 777 /home/user
