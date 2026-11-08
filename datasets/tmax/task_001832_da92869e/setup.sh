#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv curl sqlite3
    pip3 install pytest

    # Install Node.js
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/vision_engine
    mkdir -p /home/user/api_service
    mkdir -p /home/user/data

    # Create dummy video file
    touch /app/traffic_cam_04.mp4

    # Create build.sh with a bug
    cat << 'EOF' > /home/user/vision_engine/build.sh
#!/bin/bash
python3 -m venv venv
source venv/bin/activate
pip install sqlite3-api non-existent-pkg==9.9.9
EOF
    chmod +x /home/user/vision_engine/build.sh

    # Create detector.py with buggy math formula
    cat << 'EOF' > /home/user/vision_engine/detector.py
import sqlite3
import os

# Simulated extracted trajectories from video
trajectories = []
for i in range(42):
    trajectories.append({"id": f"n_{i}", "x1": 100, "y1": 400, "x2": 100, "y2": 200, "direction": "northbound"})
for i in range(17):
    trajectories.append({"id": f"s_{i}", "x1": 200, "y1": 200, "x2": 200, "y2": 400, "direction": "southbound"})

def intersect(x1, y1, x2, y2, x3, y3, x4, y4):
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if den == 0: return False

    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    # BUG: Incorrect formula for u
    u = ((x1 - x2) * (y1 - y2) - (y1 - y3) * (x1 - x3)) / den 

    if 0 <= t <= 1 and 0 <= u <= 1:
        return True
    return False

def process_video(video_path):
    db_path = '/home/user/data/traffic.db'
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS crossings (id TEXT, direction TEXT)''')

    # Virtual counting line
    x3, y3 = 0, 300
    x4, y4 = 640, 300

    for t in trajectories:
        if intersect(t['x1'], t['y1'], t['x2'], t['y2'], x3, y3, x4, y4):
            c.execute("INSERT INTO crossings VALUES (?, ?)", (t['id'], t['direction']))

    conn.commit()
    conn.close()
    print("Video processing complete.")

if __name__ == "__main__":
    process_video('/app/traffic_cam_04.mp4')
EOF

    # Create Node.js server.js with a buggy SQL query
    cat << 'EOF' > /home/user/api_service/server.js
const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const app = express();

app.get('/api/stats', (req, res) => {
    if (req.query.auth !== 'vision2024') {
        return res.status(401).json({error: 'Unauthorized'});
    }

    const db = new sqlite3.Database('/home/user/data/traffic.db');

    // BUG: Missing GROUP BY direction, so it will aggregate all rows into one incorrect result
    const query = "SELECT direction, COUNT(id) as count FROM crossings";

    db.all(query, [], (err, rows) => {
        if (err) {
            return res.status(500).json({error: err.message});
        }

        let data = {northbound: 0, southbound: 0};
        rows.forEach(r => {
            if (r.direction === 'northbound') data.northbound = r.count;
            if (r.direction === 'southbound') data.southbound = r.count;
        });

        res.json({status: 'success', data: data});
    });
});

app.listen(8080, '0.0.0.0', () => console.log('API Service listening on port 8080'));
EOF

    # Create package.json
    cat << 'EOF' > /home/user/api_service/package.json
{
  "name": "api_service",
  "version": "1.0.0",
  "description": "Traffic API Service",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "sqlite3": "^5.1.6"
  }
}
EOF

    # Install Node.js dependencies
    cd /home/user/api_service && npm install

    # Create user
    useradd -m -s /bin/bash user || true

    # Fix permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
