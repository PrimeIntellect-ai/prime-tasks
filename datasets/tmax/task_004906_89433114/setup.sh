#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server
pip3 install pytest redis

mkdir -p /app

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
sleep 1
python3 /app/populate_redis.py
EOF
chmod +x /app/start_services.sh

cat << 'EOF' > /app/populate_redis.py
import redis
import json

r = redis.Redis(host='localhost', port=6379, db=0)
r.delete('raw_logs')

# True relationship: clicks = 0.15 * views + 0
data = []
for i in range(1, 101):
    views = i * 10
    clicks = int(views * 0.15)
    r.rpush('raw_logs', json.dumps({"user_id": f"u{i}", "action": "view", "count": views}))
    r.rpush('raw_logs', json.dumps({"user_id": f"u{i}", "action": "click", "count": clicks}))
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
