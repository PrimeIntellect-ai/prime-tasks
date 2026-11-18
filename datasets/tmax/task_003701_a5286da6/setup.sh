#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nginx redis-server curl
    pip3 install pytest flask redis

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /app/oracle.py
import sys

def evaluate_rpn(expression):
    stack = []
    tokens = expression.split()
    for token in tokens:
        if token in ("+", "-", "*"):
            b = stack.pop()
            a = stack.pop()
            if token == "+":
                stack.append(a + b)
            elif token == "-":
                stack.append(a - b)
            elif token == "*":
                stack.append(a * b)
        else:
            stack.append(int(token))
    return stack[0]

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(evaluate_rpn(sys.argv[1]))
EOF
    chmod +x /app/oracle.py

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/nginx.conf
python3 /home/user/app.py &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /home/user/app.py
from flask import Flask, request
import subprocess
import redis

app = Flask(__name__)
cache = redis.Redis(host='127.0.0.1', port=9999)

@app.route('/')
def eval_rpn():
    expr = request.args.get('q', '')
    if not expr:
        return "No expression provided", 400

    try:
        cached = cache.get(expr)
        if cached:
            return cached.decode('utf-8')
    except redis.exceptions.ConnectionError:
        pass

    try:
        result = subprocess.check_output(['python3', '/app/oracle.py', expr], text=True).strip()
        try:
            cache.set(expr, result)
        except redis.exceptions.ConnectionError:
            pass
        return result
    except subprocess.CalledProcessError:
        return "Error", 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /home/user/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 127.0.0.1:8080;

        # TODO: Add location block for /api/eval to proxy to Flask
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
