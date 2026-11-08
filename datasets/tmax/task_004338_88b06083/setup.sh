#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl redis-server build-essential rustc cargo
    pip3 install pytest flask redis

    mkdir -p /home/user/data/evil /home/user/data/clean /home/user/app

    # Generate 50 evil files
    for i in $(seq 1 50); do
        if [ $((i%3)) -eq 0 ]; then
            echo "some text <script>alert(1);</script> more text" > /home/user/data/evil/evil_$i.txt
        elif [ $((i%3)) -eq 1 ]; then
            echo "click here javascript:alert(1)" > /home/user/data/evil/evil_$i.txt
        else
            echo "1 UNION SELECT * FROM users" > /home/user/data/evil/evil_$i.txt
        fi
    done

    # Generate 50 clean files
    for i in $(seq 1 50); do
        echo "This is a clean file with some safe text $i." > /home/user/data/clean/clean_$i.txt
    done

    # Create app.py
    cat << 'EOF' > /home/user/app/app.py
import os
import json
from flask import Flask, request, jsonify
import redis
import wrapper

app = Flask(__name__)
redis_url = os.environ.get('REDIS_URL', 'redis://localhost:6379')
r = redis.Redis.from_url(redis_url)

@app.route('/submit', methods=['POST'])
def submit():
    data = request.get_json()
    if not data or 'text' not in data:
        return jsonify({'error': 'No text provided'}), 400

    text = data['text']

    # Check cache
    cached = r.get(text)
    if cached is not None:
        is_clean = cached.decode('utf-8') == '1'
    else:
        is_clean = wrapper.check_text(text)
        r.set(text, '1' if is_clean else '0', ex=60)

    if is_clean:
        return jsonify({'status': 'ok'}), 200
    else:
        return jsonify({'status': 'forbidden'}), 403

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Create start.sh
    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
source /home/user/app/config.env
redis-server --daemonize yes
python3 /home/user/app/app.py &
EOF
    chmod +x /home/user/app/start.sh

    # Create config.env
    touch /home/user/app/config.env

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
