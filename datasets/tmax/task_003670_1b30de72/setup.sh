#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask requests

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/1.json
{
  "expression": "1 + 2",
  "patch": "--- a/main.py\n+++ b/main.py\n@@ -1,2 +1,2 @@\n-print('hello')\n+print('world')\n"
}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/1.json
{
  "expression": "__import__('os').system('rm -rf /')",
  "patch": "--- a/main.py\n+++ b/main.py\n@@ -1,2 +1,2 @@\n-print('hello')\n+print('world')\n"
}
EOF

    cat << 'EOF' > /app/corpus/evil/2.json
{
  "expression": "1 + 2",
  "patch": "--- /etc/passwd\n+++ /etc/passwd\n@@ -1,2 +1,2 @@\n-root:x:0:0:root:/root:/bin/bash\n+root:x:0:0:root:/root:/bin/sh\n"
}
EOF

    cat << 'EOF' > /app/corpus/evil/3.json
{
  "expression": "1 + 2",
  "patch": "--- ../../../etc/passwd\n+++ ../../../etc/passwd\n@@ -1,2 +1,2 @@\n-root:x:0:0:root:/root:/bin/bash\n+root:x:0:0:root:/root:/bin/sh\n"
}
EOF

    # Create the backend service
    cat << 'EOF' > /app/backend.py
from flask import Flask, request, jsonify
import sys

app = Flask(__name__)

@app.route('/build', methods=['POST'])
def build():
    return jsonify({"status": "success"}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF

    # A script to start the backend service (if needed by the platform)
    cat << 'EOF' > /app/start_backend.sh
#!/bin/bash
nohup python3 /app/backend.py > /app/backend.log 2>&1 &
sleep 1
EOF
    chmod +x /app/start_backend.sh

    # Start the backend service so it's running if the environment persists it (e.g. via entrypoint)
    # Note: Apptainer %post processes don't persist, but we provide the script.

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
