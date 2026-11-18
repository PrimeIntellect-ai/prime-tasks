#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server golang curl
    pip3 install pytest redis setuptools

    mkdir -p /app/py_graph_dumper
    mkdir -p /app/go-processor

    cat << 'EOF' > /app/startup.sh
#!/bin/bash
redis-server --daemonize yes
sleep 1
# Populate legacy data
redis-cli HSET legacy:nodes "node_A" '{"id": "node_A", "deps": ["node_B", "node_C"], "bytecode": "0103"}'
redis-cli HSET legacy:nodes "node_B" '{"id": "node_B", "deps": ["node_C"], "bytecode": "010103"}'
redis-cli HSET legacy:nodes "node_C" '{"id": "node_C", "deps": [], "bytecode": "00"}'
redis-cli HSET legacy:nodes "node_D" '{"id": "node_D", "deps": ["node_A"], "bytecode": "0202"}'
EOF
    chmod +x /app/startup.sh

    cat << 'EOF' > /app/py_graph_dumper/setup.py
from setuptools import setup
setup(
    name='py_graph_dumper',
    version='1.0',
    py_modules=['dumper'],
    entry_points={
        'console_scripts': [
            'dumper=dumper:main'
        ]
    }
    install_requires=['redis']
)
EOF

    cat << 'EOF' > /app/py_graph_dumper/dumper.py
import redis, json, argparse
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    print "Connecting to Redis..."
    r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)
    data = r.hgetall('legacy:nodes')
    out = []
    for k, v in data.iteritems():
        out.append(json.loads(v))
    with open(args.output, 'w') as f:
        json.dump(out, f)
EOF

    cd /app/go-processor && go mod init go-processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
