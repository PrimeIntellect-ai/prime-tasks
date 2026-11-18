#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron curl wget
    pip3 install pytest requests

    mkdir -p /app/include
    wget https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h -O /app/include/httplib.h

    cat << 'EOF' > /app/generator.py
import socket
import time
import random

def run():
    while True:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect(("127.0.0.1", 9000))
            i = 0
            while True:
                record_id = f"gen_{i}"
                ip = f"192.168.1.{random.randint(1, 254)}"
                email = f"user{i}@example.com"
                line = f"{int(time.time())},{record_id},{ip},{email},event,{i}\n"
                s.sendall(line.encode())
                if random.random() < 0.2:
                    s.sendall(line.encode())
                i += 1
                time.sleep(0.5)
        except Exception:
            time.sleep(1)

if __name__ == "__main__":
    run()
EOF

    cat << 'EOF' > /app/start_generator.sh
#!/bin/bash
python3 /app/generator.py &
EOF
    chmod +x /app/start_generator.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
