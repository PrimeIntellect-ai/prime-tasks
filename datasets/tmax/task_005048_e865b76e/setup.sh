#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask pyftpdlib redis

    mkdir -p /app/data/evil /app/data/clean /app/ftp_root/data /home/user/processed

    # Create clean files
    echo "Clean data 1" | iconv -t SHIFT-JIS > /app/data/clean/clean_1.txt
    echo "Clean data 2" > /app/data/clean/clean_2.txt

    # Create evil files
    echo "<ScRipT>alert()</script>" | iconv -t UTF-16LE > /app/data/evil/evil_1.txt
    echo "'; DROP TABLE users;" | iconv -t CP1252 > /app/data/evil/evil_2.txt

    cp /app/data/clean/* /app/ftp_root/data/
    cp /app/data/evil/* /app/ftp_root/data/

    # Create webhook script
    cat << 'EOF' > /app/webhook.py
from flask import Flask, request
app = Flask(__name__)
@app.route('/webhook', methods=['POST'])
def webhook():
    with open('/app/webhook.log', 'a') as f:
        f.write(request.data.decode('utf-8', errors='replace') + '\n')
    return "OK"
if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Ensure services start when bash is invoked
    cat << 'EOF' >> /etc/bash.bashrc
if [ ! -f /tmp/services_started ]; then
    touch /tmp/services_started
    redis-server --daemonize yes
    python3 -m pyftpdlib -p 2121 -d /app/ftp_root >/dev/null 2>&1 &
    python3 /app/webhook.py >/dev/null 2>&1 &
    sleep 2
fi
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
