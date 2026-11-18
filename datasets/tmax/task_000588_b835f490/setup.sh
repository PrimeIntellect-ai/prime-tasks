#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx supervisor openssl netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/microservices/www
    echo "Hello Microservices" > /home/user/microservices/www/index.html

    cat << 'EOF' > /home/user/microservices/mailer.sh
#!/bin/bash
while true; do
  echo -e "220 Mock SMTP Ready\n" | nc -l -p 8025 -q 1
done
EOF
    chmod +x /home/user/microservices/mailer.sh

    chmod -R 777 /home/user
