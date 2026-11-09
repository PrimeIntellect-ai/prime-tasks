#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server curl jq bc gawk
pip3 install pytest flask python-dotenv redis

mkdir -p /app

cat << 'EOF' > /app/api.py
import os
from flask import Flask, jsonify
from dotenv import load_dotenv

load_dotenv('/app/.env')

app = Flask(__name__)

@app.route('/api/users/<user_id>')
def get_user(user_id):
    try:
        uid = int(user_id.split('_')[-1])
    except ValueError:
        uid = 1
    score = 1.0 + (uid * 0.1)
    return jsonify({"risk_score": score})

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 5005))
    app.run(host='127.0.0.1', port=port)
EOF

cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
sleep 1
bash /app/setup_redis.sh
python3 /app/api.py &
EOF

cat << 'EOF' > /app/.env
PORT=5005
REDIS_URL=redis://localhost:6379/1
EOF

cat << 'EOF' > /app/oracle_process.sh
#!/bin/bash
read line
IFS=',' read -r tx_id user_id amount timestamp <<< "$line"
risk_score=$(curl -s http://127.0.0.1:5000/api/users/$user_id | jq -r '.risk_score')
limit=$(redis-cli get limit:$user_id)
adjusted=$(echo "$amount * $risk_score" | bc -l)
if $(echo "$adjusted > $limit" | bc -l | grep -q 1); then
    echo "$tx_id,REJECT"
else
    echo "$tx_id,APPROVE"
fi
EOF

cat << 'EOF' > /app/setup_redis.sh
#!/bin/bash
for i in {1..9}; do
    redis-cli set limit:user_$i $((100 + i * 500)) > /dev/null
done
EOF

chmod +x /app/start.sh /app/oracle_process.sh /app/setup_redis.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
