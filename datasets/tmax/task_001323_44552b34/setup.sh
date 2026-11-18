#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq curl bc
    pip3 install pytest flask

    mkdir -p /app
    cat << 'EOF' > /app/config.env
MODEL_PORT=8001
VECTOR_PORT=8001
DIMENSIONS=8
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
export $(grep -v '^#' /app/config.env | xargs)
python3 /app/embedding_service.py &
python3 /app/vector_search.py &
sleep 2
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/embedding_service.py
import os
import hashlib
from flask import Flask, request, jsonify

app = Flask(__name__)
port = int(os.environ.get('MODEL_PORT', 8001))
dim = int(os.environ.get('DIMENSIONS', 10))

@app.route('/embed', methods=['POST'])
def embed():
    data = request.json
    text = data.get('text', '')

    h = hashlib.md5(text.encode()).digest()
    vector = [(b / 255.0) for b in h[:dim]]

    while len(vector) < dim:
        vector.append(0.5)

    return jsonify({"vector": vector})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=port)
EOF

    cat << 'EOF' > /app/vector_search.py
import os
from flask import Flask, request, jsonify

app = Flask(__name__)
port = int(os.environ.get('VECTOR_PORT', 8002))

@app.route('/distance', methods=['POST'])
def distance():
    data = request.json
    vector = data.get('vector', [])

    if not vector:
        return jsonify({"distance": 0.0})

    # Simple mock distance: first element * 10
    dist = vector[0] * 10.0
    return jsonify({"distance": dist})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=port)
EOF

    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # md5("clean").digest()[0] = 104 -> 104/255 * 10 = 4.07 (<= 5.0)
    cat << 'EOF' > /home/user/corpora/clean/paper1.json
{"id": "1", "abstract": "clean", "metadata": {"source": "nature"}}
EOF

    # Rejected by source
    cat << 'EOF' > /home/user/corpora/evil/paper2.json
{"id": "2", "abstract": "clean", "metadata": {"source": "predatory_journal_x"}}
EOF

    # md5("evil").digest()[0] = 223 -> 223/255 * 10 = 8.74 (> 5.0)
    cat << 'EOF' > /home/user/corpora/evil/paper3.json
{"id": "3", "abstract": "evil", "metadata": {"source": "nature"}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
