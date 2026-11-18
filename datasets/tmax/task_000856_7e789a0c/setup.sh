#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server
pip3 install pytest flask redis

mkdir -p /home/user/api
cat << 'EOF' > /home/user/api/app.py
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.get_data()
    r.rpush('data_queue', data)
    return 'OK', 200

if __name__ == '__main__':
    app.run(port=8080)
EOF

cat << 'EOF' > /start_services.sh
#!/bin/bash
if ! pgrep -x "redis-server" > /dev/null; then
    redis-server --daemonize yes
fi
if ! pgrep -f "python3 /home/user/api/app.py" > /dev/null; then
    nohup python3 /home/user/api/app.py > /dev/null 2>&1 &
    sleep 2
fi
EOF
chmod +x /start_services.sh

echo "/start_services.sh" >> /etc/bash.bashrc
echo "/start_services.sh" >> /root/.bashrc

useradd -m -s /bin/bash user || true
echo "/start_services.sh" >> /home/user/.bashrc

chmod -R 777 /home/user
