#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /app

    # Create the oracle processor
    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys, json, math

def calc_corr(x, y):
    if len(x) < 2: return None
    mean_x = sum(x)/len(x)
    mean_y = sum(y)/len(y)
    var_x = sum((xi - mean_x)**2 for xi in x)
    var_y = sum((yi - mean_y)**2 for yi in y)
    if var_x == 0 or var_y == 0: return None
    cov = sum((xi - mean_x)*(yi - mean_y) for xi, yi in zip(x, y))
    return round(cov / math.sqrt(var_x * var_y), 4)

def main():
    try:
        data = json.load(sys.stdin)
    except:
        print(json.dumps({"valid_joined_records":0,"correlation":None}, separators=(',', ':')))
        return

    users_map = {}
    for u in data.get("users", []):
        if type(u) is dict and type(u.get("user_id")) is int and type(u.get("age")) is int and u["age"] >= 0:
            if u["user_id"] not in users_map:
                users_map[u["user_id"]] = u["age"]

    events_map = {}
    for e in data.get("events", []):
        if type(e) is dict and type(e.get("user_id")) is int and type(e.get("clicks")) is int and e["clicks"] >= 0 and type(e.get("time")) in (int, float) and e["time"] >= 0:
            if e["user_id"] not in events_map:
                events_map[e["user_id"]] = e["clicks"]

    joined_x, joined_y = [], []
    for uid, age in users_map.items():
        if uid in events_map:
            joined_x.append(age)
            joined_y.append(events_map[uid])

    corr = calc_corr(joined_x, joined_y)
    print(json.dumps({"valid_joined_records": len(joined_x), "correlation": corr}, separators=(',', ':')))

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_processor

    # Create the tracker API
    cat << 'EOF' > /app/tracker_api.py
import os
from flask import Flask
import redis

app = Flask(__name__)
r = redis.Redis(host=os.environ.get('REDIS_HOST', 'localhost'), port=6379, db=0)

@app.route('/health')
def health():
    try:
        r.ping()
        return "OK", 200
    except:
        return "ERROR", 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=int(os.environ.get('TRACKER_PORT', 8080)))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
