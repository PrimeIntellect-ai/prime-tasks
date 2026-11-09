#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        curl \
        nodejs \
        npm \
        cargo \
        rustc

    pip3 install pytest flask redis

    mkdir -p /app/services
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create Flask Sequence Provider
    cat << 'EOF' > /app/services/provider.py
from flask import Flask
import os
import redis

app = Flask(__name__)

@app.route('/baseline_score')
def baseline():
    return "4.25"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Create Express Aggregator
    cd /app/services
    npm init -y
    npm install express
    cat << 'EOF' > /app/services/aggregator.js
const express = require('express');
const app = express();
app.use(express.json());

app.post('/flag', (req, res) => {
    console.log("Flagged:", req.body.filename);
    res.sendStatus(200);
});

app.listen(3000, () => console.log('Aggregator running on port 3000'));
EOF

    # Create buggy start script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
# Buggy startup script
redis-server --port 6380 &
cd /app/services
python3 provider.py &
node aggregator.js &
EOF
    chmod +x /app/start_services.sh

    # Generate corpora
    for i in $(seq 1 50); do
        echo ">clean_$i" > /app/corpora/clean/clean_$i.fasta
        cat /dev/urandom | tr -dc 'ACGT' | fold -w 100 | head -n 1 >> /app/corpora/clean/clean_$i.fasta

        echo ">evil_$i" > /app/corpora/evil/evil_$i.fasta
        yes "ACG" | tr -d '\n' | head -c 100 >> /app/corpora/evil/evil_$i.fasta
        echo "" >> /app/corpora/evil/evil_$i.fasta
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
