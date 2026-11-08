#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget ffmpeg sqlite3 curl
    pip3 install pytest numpy opencv-python-headless

    # Install Go 1.21
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile

    # Create directories
    mkdir -p /app/corpus
    mkdir -p /home/user

    # Generate video with white flashes
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

width, height = 640, 480
fps = 30
duration = 10
total_frames = fps * duration

out = cv2.VideoWriter('/app/server_rack.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))

flash_frames = [45, 112, 280]

for i in range(total_frames):
    if i in flash_frames:
        frame = np.ones((height, width, 3), dtype=np.uint8) * 255
    else:
        frame = np.zeros((height, width, 3), dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py

    # Create SQLite Database
    sqlite3 /home/user/system.db << 'EOF'
CREATE TABLE events (id INTEGER PRIMARY KEY, service_id TEXT, event_time TIMESTAMP, impact_score INTEGER);
INSERT INTO events (service_id, event_time, impact_score) VALUES ('svc1', '2023-01-01 10:00:00', 10);
INSERT INTO events (service_id, event_time, impact_score) VALUES ('svc1', '2023-01-01 10:05:00', 20);
INSERT INTO events (service_id, event_time, impact_score) VALUES ('svc1', '2023-01-01 10:10:00', 30);
INSERT INTO events (service_id, event_time, impact_score) VALUES ('svc1', '2023-01-01 10:15:00', 40);
INSERT INTO events (service_id, event_time, impact_score) VALUES ('svc2', '2023-01-01 10:02:00', 5);
INSERT INTO events (service_id, event_time, impact_score) VALUES ('svc2', '2023-01-01 10:07:00', 15);
INSERT INTO events (service_id, event_time, impact_score) VALUES ('svc2', '2023-01-01 10:12:00', 25);
CREATE INDEX idx_events ON events(event_time);
PRAGMA writable_schema = 1;
UPDATE sqlite_master SET sql='CREATE INDEX idx_events ON events(wrong_column)' WHERE name='idx_events';
PRAGMA writable_schema = 0;
EOF

    # Create corpus files
    cat << 'EOF' > /app/corpus/evil.txt
SELECT * FROM users UNION SELECT password FROM admin;
DROP TABLE events;
UPDATE events SET impact_score=0;
DELETE FROM events WHERE id=1;
INSERT INTO events (service_id) VALUES ('evil');
EOF

    cat << 'EOF' > /app/corpus/clean.txt
SELECT id, event_time FROM events WHERE impact_score > 5;
WITH cte AS (SELECT * FROM events) SELECT count(*) FROM cte;
SELECT service_id, sum(impact_score) FROM events GROUP BY service_id;
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
