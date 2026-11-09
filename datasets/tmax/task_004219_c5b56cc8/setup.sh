#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server gcc
    pip3 install pytest flask redis

    # Hack to ensure redis is running when python/pytest is invoked
    mv /usr/bin/python3 /usr/bin/python3.real
    cat << 'EOF' > /usr/bin/python3
#!/bin/bash
if ! pgrep -x "redis-server" > /dev/null; then
    redis-server --daemonize yes
fi
exec /usr/bin/python3.real "$@"
EOF
    chmod +x /usr/bin/python3

    mkdir -p /home/user/app/clib

    cat << 'EOF' > /home/user/app/clib/scheduler.c
struct Node {
    int id;
    int dep;
};
struct Graph {
    struct Node* nodes;
    int count;
};
int schedule(struct Graph g) {
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/api.py
from flask import Flask
app = Flask(__name__)
@app.route('/submit', methods=['POST'])
def submit():
    return "ok"
if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/app/worker.py
import ctypes
class Node(ctypes.Structure):
    _fields_ = [("id", ctypes.c_int)]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
