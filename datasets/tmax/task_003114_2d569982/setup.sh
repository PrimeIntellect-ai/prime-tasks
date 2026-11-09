#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl nodejs npm
    pip3 install pytest fastapi uvicorn redis

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app/data_ingest
    mkdir -p /home/user/app/scoring_service

    cat << 'EOF' > /home/user/app/raw_texts.json
[
  {"id": "1", "text": "This is a very long document that has more than twenty words so it should get a high score from the scoring service which is good."},
  {"id": "2", "text": "Short doc."},
  {"id": "3", "text": "Another short one."},
  {"id": "4", "text": "This document is also quite long and contains many words to ensure a high score is given by the logic."},
  {"id": "5", "text": "Medium length document with some words here and there."},
  {"id": "6", "text": "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z"},
  {"id": "7", "text": "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty."},
  {"id": "8", "text": "Bad doc"},
  {"id": "9", "text": "Terrible"},
  {"id": "10", "text": "Very very very very very very very very very very very very very very very very very very very very good."}
]
EOF

    cat << 'EOF' > /home/user/app/data_ingest/package.json
{
  "name": "data_ingest",
  "version": "1.0.0",
  "dependencies": {
    "redis": "^4.6.7"
  }
}
EOF

    cat << 'EOF' > /home/user/app/data_ingest/index.js
const redis = require('redis');
const fs = require('fs');

async function run() {
    const client = redis.createClient({ url: 'redis://localhost:9999' });
    await client.connect();

    const data = JSON.parse(fs.readFileSync('../raw_texts.json', 'utf8'));
    for (const doc of data) {
        await client.rPush('doc_queue', JSON.stringify(doc));
    }
    console.log("Done");
    process.exit(0);
}
run();
EOF

    cd /home/user/app/data_ingest && npm install

    cat << 'EOF' > /home/user/app/scoring_service/main.py
from fastapi import FastAPI
import redis
import json

app = FastAPI()
r = redis.Redis(host='localhost', port=6379, db=0)

@app.get("/process_next")
def process_next():
    item = r.lpop("doc_queue")
    if not item:
        return {"error": "queue empty"}
    doc = json.loads(item)
    text = doc.get("text", "")
    tokens = text.split()
    score = min(len(tokens) / 20.0, 1.0)
    return {"id": doc["id"], "tokens": tokens, "score": score}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3000)
EOF

    chmod -R 777 /home/user
