#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        sqlite3 \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        socat \
        netcat-openbsd \
        curl \
        jq

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create SQLite database
    sqlite3 /home/user/graph.db <<EOF
CREATE TABLE nodes (id TEXT, group_id TEXT);
CREATE TABLE edges (src TEXT, dst TEXT, group_id TEXT);

INSERT INTO nodes VALUES ('N1', 'G1'), ('N1', 'G2'), ('N2', 'G1'), ('N3', 'G2');
INSERT INTO edges VALUES ('N1', 'N2', 'G1'), ('N1', 'N3', 'G1'), ('N1', 'N2', 'G1');
INSERT INTO edges VALUES ('N1', 'N3', 'G2');
INSERT INTO edges VALUES ('N2', 'N1', 'G1'), ('N2', 'N3', 'G1');
EOF

    # Create compute_metrics script
    cat << 'EOF' > /home/user/compute_metrics.sh
#!/bin/bash
sqlite3 /home/user/graph.db <<SQL
SELECT nodes.id AS node_id, count(edges.dst) AS centrality
FROM nodes
JOIN edges ON nodes.id = edges.src
GROUP BY nodes.id
ORDER BY centrality DESC, node_id ASC
LIMIT 3;
SQL
EOF
    chmod +x /home/user/compute_metrics.sh

    # Create schema_clue image
    mkdir -p /app
    convert -size 1000x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -annotate +10+50 'Ensure your graph projection uses both keys: JOIN nodes ON nodes.id = edges.src AND nodes.group_id = edges.group_id' \
        /app/schema_clue.png

    chmod -R 777 /home/user
    chmod -R 777 /app
