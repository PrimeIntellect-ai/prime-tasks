#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3 jq socat curl netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create a dummy video file at /app/incident.mp4 (30fps, 10 seconds)
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/incident.mp4

    # 2. Create the telemetry database
    sqlite3 /home/user/telemetry.db <<EOF
CREATE TABLE events (frame_idx INTEGER, timestamp_utc TEXT, value REAL);
INSERT INTO events VALUES (164, '2023-10-27T02:00:05.466Z', 1.2);
INSERT INTO events VALUES (165, '2023-10-27T02:00:05.500Z', 1.5);
INSERT INTO events VALUES (166, '2023-10-27T02:00:05.533Z', 9.9);
INSERT INTO events VALUES (167, '2023-10-27T02:00:05.566Z', 10.1);
INSERT INTO events VALUES (168, '2023-10-27T02:00:05.600Z', 10.5);
INSERT INTO events VALUES (169, '2023-10-27T02:00:05.633Z', 8.2);
EOF

    # 3. Create the intentionally buggy scripts
    cat << 'EOF' > /home/user/triage.sh
#!/bin/bash
# Bug 1 & 2: awk float precision and 1-based NR instead of 0-based index
ffprobe -v error -select_streams v:0 -show_entries packet=duration_time -of default=noprint_wrappers=1:nokey=1 /app/incident.mp4 > durations.txt
CRITICAL_FRAME=$(awk '{sum+=$1} sum>5.5 {print NR; exit}' durations.txt)

# Bug 3: SQLite query is broken due to off-by-one and wrong formatting
sqlite3 /home/user/telemetry.db "SELECT * FROM events WHERE frame_idx >= $CRITICAL_FRAME LIMIT 3;" > /home/user/incident_data.txt
# (Agent must fix query to > critical_frame, and output JSON)
EOF
    chmod +x /home/user/triage.sh

    cat << 'EOF' > /home/user/server.sh
#!/bin/bash
# A broken netcat/socat or python server stub
# Agent needs to rewrite this to serve /home/user/incident_data.json on port 8080 with auth
EOF
    chmod +x /home/user/server.sh

    chmod -R 777 /home/user
