#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 ffmpeg python3-opencv
    pip3 install pytest

    mkdir -p /app

    # Generate surveillance video using ffmpeg with ultrafast preset to avoid build timeout
    # 1 hour (3600 seconds) at 1 fps. Door opens at 45, 120, 310, 850, 1105, 1920, 2400, 3115, 3500
    ffmpeg -f lavfi -i color=c=black:s=1920x1080:r=1:d=3600 -vf "drawbox=x=1870:y=10:w=50:h=50:color=red@1:t=fill:enable='eq(n\,45)+eq(n\,120)+eq(n\,310)+eq(n\,850)+eq(n\,1105)+eq(n\,1920)+eq(n\,2400)+eq(n\,3115)+eq(n\,3500)'" -c:v libx264 -preset ultrafast -crf 51 -y /app/surveillance.mp4

    # Create SQLite Database and populate it
    cat << 'EOF' > /app/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/app/access_logs.db')
c = conn.cursor()
c.execute('CREATE TABLE badge_scans (id INT, badge_id INT, door_id INT, scan_time INT)')
c.execute('CREATE TABLE camera_events (id INT, door_id INT, event_time INT)')

# Ground truth camera events for door 1
gt_events = [45, 120, 310, 850, 1105, 1920, 2400, 3115, 3500]
badge_ids = [101, 102, 103, 104, 105]

# Insert 50 random badge scans
random.seed(42)
for i in range(1, 51):
    badge = random.choice(badge_ids)
    door = random.choice([1, 2, 3])
    # Make some scans match the events
    if random.random() < 0.3:
        scan_time = random.choice(gt_events) + random.randint(-5, 5)
        door = 1
    else:
        scan_time = random.randint(0, 3600)
    c.execute('INSERT INTO badge_scans VALUES (?, ?, ?, ?)', (i, badge, door, scan_time))

conn.commit()
conn.close()
EOF
    python3 /app/setup_db.py
    rm /app/setup_db.py

    # Create buggy script
    cat << 'EOF' > /app/generate_report.py
import sqlite3
def generate_report(badge_id):
    conn = sqlite3.connect('/app/access_logs.db')
    c = conn.cursor()
    query = "SELECT count(*) FROM badge_scans bs, camera_events ce WHERE bs.badge_id = ?;"
    c.execute(query, (badge_id,))
    return c.fetchone()[0]
EOF

    # Create oracle script
    cat << 'EOF' > /app/oracle_audit_query.py
import sys
import sqlite3

def main():
    badge_id = int(sys.argv[1])
    start_time = int(sys.argv[2])
    end_time = int(sys.argv[3])

    conn = sqlite3.connect('/app/access_logs.db')
    c = conn.cursor()

    gt_events = [45, 120, 310, 850, 1105, 1920, 2400, 3115, 3500]

    c.execute('SELECT scan_time FROM badge_scans WHERE badge_id = ? AND door_id = 1 AND scan_time >= ? AND scan_time <= ?', (badge_id, start_time, end_time))
    scans = c.fetchall()

    count = 0
    for (scan_time,) in scans:
        for ev in gt_events:
            if abs(scan_time - ev) <= 5:
                count += 1
                break

    print(count)

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
