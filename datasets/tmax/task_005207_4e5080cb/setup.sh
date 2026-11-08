#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/services

    cat << 'EOF' > /home/user/services/producer.py
import time
import socket
import logging
import threading

logging.basicConfig(filename='/home/user/services/app.log', level=logging.INFO, format='%(asctime)s %(levelname)s SERVICE_A - %(message)s')

def serve():
    time.sleep(5) # Simulate slow startup
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 8080))
    s.listen(1)
    logging.info("Started listening on 8080")
    while True:
        conn, addr = s.accept()
        data = conn.recv(1024)
        if b"PING" in data:
            logging.error("ERR_404 File not found")
            logging.critical("CRIT_992 Database timeout")
            logging.info("Request processed")
            logging.critical("CRIT_105 Memory leak detected")
            conn.sendall(b"PONG")
        conn.close()

t = threading.Thread(target=serve)
t.daemon = True
t.start()
while True:
    time.sleep(1)
EOF

    cat << 'EOF' > /home/user/services/consumer.py
import socket
import time
import sys

def run():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8080))
        s.sendall(b"PING")
        data = s.recv(1024)
        s.close()
        if b"PONG" in data:
            with open('/home/user/services/consumer_success.flag', 'w') as f:
                f.write("OK\n")
    except Exception as e:
        sys.exit(1)

run()
while True:
    time.sleep(1)
EOF

    cat << 'EOF' > /home/user/services/start_services.sh
#!/bin/bash
python3 /home/user/services/producer.py &
python3 /home/user/services/consumer.py &
EOF

    chmod +x /home/user/services/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
