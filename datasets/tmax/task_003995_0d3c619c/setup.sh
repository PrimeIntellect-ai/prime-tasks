#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3 jq curl
    pip3 install pytest

    mkdir -p /app

    # Generate experiment.mp4
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=30 -c:v libx264 /app/experiment.mp4

    # Create sensors.db
    sqlite3 /app/sensors.db <<EOF
CREATE TABLE readings (id INTEGER PRIMARY KEY, timestamp INTEGER, value REAL);
INSERT INTO readings (id, timestamp, value) VALUES
(1, 100, 10.0),
(2, 101, 12.0),
(3, 102, 15.0),
(4, 103, 9.0),
(5, 104, 20.0),
(6, 105, 25.0),
(7, 106, 2.0);
EOF

    # Create taxonomy.json
    cat << 'EOF' > /app/taxonomy.json
{
  "name": "root",
  "children": [
    {
      "name": "baseline",
      "children": []
    },
    {
      "name": "experiments",
      "children": [
        {
          "name": "control",
          "children": []
        },
        {
          "name": "active",
          "children": [
            {
              "name": "TargetAnomaly"
            }
          ]
        }
      ]
    }
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
