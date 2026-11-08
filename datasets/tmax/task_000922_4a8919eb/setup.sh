#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies
    apt-get install -y ffmpeg sqlite3 libsqlite3-dev nlohmann-json3-dev build-essential wget

    mkdir -p /app

    # Generate video parts with hex colors to avoid ffmpeg color name issues
    ffmpeg -f lavfi -i "color=c=0x000000:s=100x100:d=2" -c:v libx264 -y /tmp/part1.mp4
    ffmpeg -f lavfi -i "color=c=0x808080:s=100x100:d=2" -c:v libx264 -y /tmp/part2.mp4
    ffmpeg -f lavfi -i "color=c=0xFFFFFF:s=100x100:d=2" -c:v libx264 -y /tmp/part3.mp4
    ffmpeg -f lavfi -i "color=c=0x666666:s=100x100:d=2" -c:v libx264 -y /tmp/part4.mp4
    ffmpeg -f lavfi -i "color=c=0xBFBFBF:s=100x100:d=2" -c:v libx264 -y /tmp/part5.mp4

    cat << 'EOF' > /tmp/inputs.txt
file '/tmp/part1.mp4'
file '/tmp/part2.mp4'
file '/tmp/part3.mp4'
file '/tmp/part4.mp4'
file '/tmp/part5.mp4'
EOF

    ffmpeg -f concat -safe 0 -i /tmp/inputs.txt -c copy /app/dataset_recording.mp4

    # Create graph.json
    cat << 'EOF' > /app/graph.json
{
  "A": {"B": 10, "C": 5},
  "B": {"C": 2, "D": 1},
  "C": {"B": 3, "D": 9, "E": 2},
  "D": {"E": 4},
  "E": {"D": 6, "A": 7}
}
EOF

    # Create SQLite DB
    sqlite3 /app/metadata.db << 'EOF'
CREATE TABLE subjects (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO subjects (id, name) VALUES (1, 'Subject01');
CREATE TABLE epochs (subject_id INTEGER, epoch_index INTEGER, activity_level INTEGER);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
