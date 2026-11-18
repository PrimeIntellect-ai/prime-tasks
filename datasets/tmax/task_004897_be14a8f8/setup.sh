#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        nodejs \
        npm

    pip3 install pytest

    mkdir -p /app/logs

    cat << 'EOF' > /app/logs/ingest.log
2023-11-10T08:14:00Z INFO Processing TXN-8841
2023-11-10T08:14:02Z INFO Processing TXN-8842
2023-11-10T08:14:05Z ERROR Failed to parse payload for TXN-8842: missing field
EOF

    cat << 'EOF' > /app/logs/api.log
2023-11-10T08:14:01Z INFO Received request for TXN-8841
2023-11-10T08:14:03Z ERROR API timeout waiting for TXN-8842 parts
EOF

    # Generate the configuration snapshot image
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"API_PORT=9092\nAPI_KEY=KAPPA-881-ALPHA" /app/config_snapshot.png

    cat << 'EOF' > /app/api.js
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
const secretKey = process.env.SECRET_KEY;

app.get('/health', (req, res) => {
    if (req.headers['x-api-key'] === secretKey) {
        res.status(200).send('OK');
    } else {
        res.status(403).send('Forbidden');
    }
});

app.listen(port, () => {
    console.log(`API listening on port ${port}`);
});
EOF

    cd /app
    npm init -y
    npm install express

    cat << 'EOF' > /app/ingest.py
import json

def process_data(data_str):
    data = json.loads(data_str)
    # Deliberate flaw: assuming payload and user_id exist without checking
    user_id = data["payload"]["user_id"]
    print(f"Processing user {user_id}")

if __name__ == "__main__":
    test_data = '{"id": "TXN-8842", "payload": {}}'
    process_data(test_data)
EOF

    cat << 'EOF' > /app/requirements.txt
requests==2.25.1
urllib3>=1.26.5,<1.27
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
