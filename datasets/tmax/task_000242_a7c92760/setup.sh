#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.sh
#!/bin/bash
cd /home/user

# Install MongoDB locally without root
wget -q https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-6.0.4.tgz
tar -zxf mongodb-linux-x86_64-ubuntu2204-6.0.4.tgz
mkdir -p /home/user/mongo_data

./mongodb-linux-x86_64-ubuntu2204-6.0.4/bin/mongod --dbpath /home/user/mongo_data --port 27017 --fork --logpath /home/user/mongo.log

# Wait for mongo to start
sleep 3

# Create a python script to populate data
cat << 'INNER_EOF' > /home/user/populate.py
import json
from pymongo import MongoClient

client = MongoClient("mongodb://localhost:27017/")
db = client["audit"]
collection = db["financial_tx"]

data = [
    # Cycle 1: A -> B -> C -> A
    {"sender": "AccA", "receiver": "AccB", "amount": 6000},
    {"sender": "AccA", "receiver": "AccB", "amount": 5000}, # Total 11000
    {"sender": "AccB", "receiver": "AccC", "amount": 15000},
    {"sender": "AccC", "receiver": "AccA", "amount": 12000},

    # Cycle 2: C -> D -> E -> C
    {"sender": "AccC", "receiver": "AccD", "amount": 20000},
    {"sender": "AccD", "receiver": "AccE", "amount": 15000},
    {"sender": "AccE", "receiver": "AccC", "amount": 11000},

    # Non-cycle
    {"sender": "AccF", "receiver": "AccG", "amount": 15000},
    {"sender": "AccG", "receiver": "AccH", "amount": 12000},

    # Noise (Below 10000)
    {"sender": "AccH", "receiver": "AccA", "amount": 9000},
    {"sender": "AccE", "receiver": "AccF", "amount": 5000}
]

collection.insert_many(data)
INNER_EOF

pip3 install pymongo networkx
python3 /home/user/populate.py
EOF

    chmod +x /home/user/setup_db.sh
    chmod -R 777 /home/user
