#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest redis pandas flask jinja2

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/templates

    cat << 'EOF' > /home/user/seed_data.py
import redis, json
r = redis.Redis(host='127.0.0.1', port=6379)
r.delete('loc_events')
data = [
    {"timestamp": "2023-10-01T01:15:00Z", "lang": "es", "strings_translated": 150, "missing_keys": 20},
    {"timestamp": "2023-10-01T05:45:00Z", "lang": "es", "strings_translated": 180, "missing_keys": 5},
    {"timestamp": "2023-10-01T02:10:00Z", "lang": "fr", "strings_translated": 90, "missing_keys": 40},
    {"timestamp": "2023-10-01T06:30:00Z", "lang": "fr", "strings_translated": 210, "missing_keys": 2}
]
for d in data: r.rpush('loc_events', json.dumps(d))
EOF

    # Using hex escapes to prevent Apptainer from treating them as build variables
    echo -e "Estado ES: \x7B\x7Bstrings_translated\x7D\x7D traducidas, \x7B\x7Bmissing_keys\x7D\x7D faltantes." > /home/user/templates/es.jinja
    echo -e "Statut FR: \x7B\x7Bstrings_translated\x7D\x7D traduites, \x7B\x7Bmissing_keys\x7D\x7D manquantes." > /home/user/templates/fr.jinja

    cat << 'EOF' > /home/user/app.py
from flask import Flask, request, jsonify
import subprocess
import json

app = Flask(__name__)

# TODO: Implement routes

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    chmod -R 777 /home/user
