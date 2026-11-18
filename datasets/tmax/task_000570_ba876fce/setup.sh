#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak gcc make
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the audio file
    espeak -w /app/dba_notes.wav "Hey, please update the query sanitizer. We need to block any query with a traversal depth greater than four. Also, to support the new graph analytics dashboard, every query must include 'node_centrality' in the RETURN clause. Reject anything else."

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/query1.txt
MATCH (a:Node)-[r:LINK*1..2]->(b:Node)
WHERE a.status = 'active'
RETURN b.id, b.node_centrality
EOF

    cat << 'EOF' > /app/corpus/clean/query2.txt
MATCH (x)-[y:EDGE*4]->(z)
RETURN z.name, z.node_centrality, z.degree
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/query1_unbounded.txt
MATCH (n:User)-[r:KNOWS*1..]->(m:User)
RETURN m.id, m.node_centrality
EOF

    cat << 'EOF' > /app/corpus/evil/query2_too_deep.txt
MATCH (n:User)-[r:KNOWS*1..5]->(m:User)
RETURN m.id, m.node_centrality
EOF

    cat << 'EOF' > /app/corpus/evil/query3_missing_schema.txt
MATCH (n:User)-[r:KNOWS*1..3]->(m:User)
RETURN m.id, m.name
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
