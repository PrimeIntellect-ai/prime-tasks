#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 ffmpeg tesseract-ocr fonts-dejavu
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create the SQLite Database
    sqlite3 /home/user/network.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO nodes VALUES (1, 'Alpha'), (2, 'Bravo'), (3, 'Charlie'), (4, 'Delta'), (5, 'Echo');

CREATE TABLE links (source_id INTEGER, target_id INTEGER, distance INTEGER);
INSERT INTO links VALUES (1, 3, 15);
INSERT INTO links VALUES (3, 5, 20);
INSERT INTO links VALUES (5, 2, 10);
INSERT INTO links VALUES (2, 4, 35);
INSERT INTO links VALUES (4, 1, 50);
EOF

    # 2. Create the bad SQL script (Implicit cross join)
    cat << 'EOF' > /home/user/export_edges.sql
-- Bad query causing cross join duplication
SELECT n1.id AS source, n2.id AS target, l.distance
FROM nodes n1, nodes n2, links l;
EOF

    # 3. Create the Video Fixture (/app/routing_sim.mp4)
    mkdir -p /app
    ffmpeg -y -f lavfi -i color=c=white:s=320x240:d=5 \
    -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='1':fontcolor=black:fontsize=120:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,0,1)', \
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='3':fontcolor=black:fontsize=120:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,1,2)', \
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='5':fontcolor=black:fontsize=120:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2,3)', \
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='2':fontcolor=black:fontsize=120:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,3,4)', \
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='4':fontcolor=black:fontsize=120:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,4,5)'" \
    -r 1 /app/routing_sim.mp4

    chmod -R 777 /app
    chmod -R 777 /home/user
