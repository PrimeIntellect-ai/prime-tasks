#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx redis-server procps
pip3 install pytest flask redis

mkdir -p /app/src /app/deploy

cat << 'EOF' > /app/src/app.py
from flask import Flask
import redis_utils, routes
app = Flask(__name__)
app.register_blueprint(routes.bp)
if __name__ == "__main__":
    app.run(port=5000)
EOF

cat << 'EOF' > /app/src/redis_utils.py
import redis, connection
def ping_redis():
    r = connection.get_conn()
    return r.ping()
EOF

cat << 'EOF' > /app/src/connection.py
import redis
def get_conn():
    return redis.Redis(host='127.0.0.1', port=6379)
EOF

cat << 'EOF' > /app/src/routes.py
from flask import Blueprint
import redis_utils
bp = Blueprint('routes', __name__)
@bp.route('/health')
def health():
    if redis_utils.ping_redis():
        return "OK", 200
    return "FAIL", 500
EOF

for i in $(seq 1 20); do
    dd if=/dev/urandom of=/app/src/dummy_${i}.py bs=1024 count=5 2>/dev/null
done

cat << 'EOF' > /app/src/deps.txt
app.py: redis_utils.py, routes.py
routes.py: redis_utils.py
redis_utils.py: connection.py
connection.py: 
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /app

# Ensure Redis starts when the container is executed
echo 'if ! pgrep redis-server > /dev/null; then redis-server --daemonize yes; fi' > /.singularity.d/env/99-redis.sh
chmod +x /.singularity.d/env/99-redis.sh

chmod -R 777 /home/user
