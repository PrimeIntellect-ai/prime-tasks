#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr sqlite3 fonts-dejavu-core
    pip3 install pytest flask

    mkdir -p /app

    # Create the SQLite database
    sqlite3 /app/network.db <<EOF
CREATE TABLE edges (parent_id TEXT, child_id TEXT);
INSERT INTO edges VALUES ('NODE_77', 'NODE_80');
INSERT INTO edges VALUES ('NODE_77', 'NODE_81');
INSERT INTO edges VALUES ('NODE_80', 'NODE_90');
INSERT INTO edges VALUES ('NODE_90', 'NODE_95');
INSERT INTO edges VALUES ('NODE_10', 'NODE_11');
EOF

    # Create the video file
    ffmpeg -f lavfi -i color=c=white:s=640x480:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='NODE_77':x=(w-text_w)/2:y=(h-text_h)/2:fontsize=72:fontcolor=black:enable='between(t,3,3.1)'" -c:v libx264 -r 30 -pix_fmt yuv420p /app/infection_map.mp4

    useradd -m -s /bin/bash user || true

    # Create the broken API script
    cat << 'EOF' > /home/user/api.py
from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)

@app.route('/trace', methods=['GET'])
def trace():
    start_node = request.args.get('start_node')
    conn = sqlite3.connect('/app/network.db')
    cursor = conn.cursor()
    # The implicit cross join bug is here: "FROM edges e, path p" with no join condition
    query = f"""
    WITH RECURSIVE path(id) AS (
        SELECT '{start_node}'
        UNION ALL
        SELECT e.child_id FROM edges e, path p
    )
    SELECT DISTINCT id FROM path;
    """
    cursor.execute(query)
    results = [row[0] for row in cursor.fetchall()]
    return jsonify({"infected_nodes": results})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
