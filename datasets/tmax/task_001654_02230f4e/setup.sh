#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip postgresql postgresql-contrib redis-server sudo
    pip3 install pytest flask psycopg2-binary redis pydantic sqlalchemy requests

    mkdir -p /app

    cat << 'EOF' > /app/api.py
from flask import Flask, request, jsonify
import psycopg2
import redis
from pydantic import BaseModel
from typing import List

app = Flask(__name__)

# Bug: wrong port for redis (should be 6379)
cache = redis.Redis(host='localhost', port=6378, db=0)

def get_db_connection():
    return psycopg2.connect(dbname='app_db', user='postgres', host='localhost')

class Event(BaseModel):
    id: int
    user_id: int
    event_type: str
    cost: float
    timestamp: str

class ResponseModel(BaseModel):
    user_id: int
    total_cost: float
    events: List[Event]

@app.route('/events', methods=['GET'])
def get_events():
    user_id = int(request.args.get('user_id', 1))
    page = int(request.args.get('page', 1))
    limit = int(request.args.get('limit', 50))

    cache_key = f"user_summary_{user_id}"
    try:
        cached = cache.get(cache_key)
        if cached:
            pass # Should use cached total_cost
    except:
        pass

    conn = get_db_connection()
    cur = conn.cursor()
    # Inefficient query fetching all events
    cur.execute("SELECT id, user_id, event_type, cost, timestamp FROM events")
    rows = cur.fetchall()
    cur.close()
    conn.close()

    user_events = []
    total_cost = 0.0
    for r in rows:
        if r[1] == user_id:
            user_events.append({
                "id": r[0],
                "user_id": r[1],
                "event_type": r[2],
                "cost": float(r[3]),
                "timestamp": str(r[4])
            })
            total_cost += float(r[3])

    # Sort and paginate in Python
    user_events.sort(key=lambda x: x['timestamp'], reverse=True)
    start = (page - 1) * limit
    end = start + limit
    paginated = user_events[start:end]

    try:
        cache.setex(cache_key, 60, str(total_cost))
    except:
        pass

    return jsonify({
        "user_id": user_id,
        "total_cost": total_cost,
        "events": paginated
    })

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
service postgresql start
service redis-server start

sleep 2

su - postgres -c "psql -c \"CREATE DATABASE app_db;\"" || true
su - postgres -c "psql -d app_db -c \"
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    user_id INT,
    event_type VARCHAR(50),
    cost NUMERIC,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
\""

COUNT=$(su - postgres -c "psql -d app_db -tAc \"SELECT COUNT(*) FROM events;\"" || echo "0")
if [ "$COUNT" -lt 500000 ]; then
    su - postgres -c "psql -d app_db -c \"
    INSERT INTO events (user_id, event_type, cost, timestamp)
    SELECT 
        (random() * 1000 + 1)::int,
        'click',
        random() * 10,
        NOW() - (random() * interval '30 days')
    FROM generate_series(1, 500000);
    \""
fi

nohup python3 /app/api.py > /tmp/api.log 2>&1 &
sleep 2
EOF

    chmod +x /app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
