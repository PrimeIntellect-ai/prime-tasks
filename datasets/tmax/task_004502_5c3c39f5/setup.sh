#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick
    pip3 install pytest

    # Create directories
    mkdir -p /app/clean
    mkdir -p /app/evil

    # Generate the optimization_rules.png image
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 16 -fill black \
    -draw "text 20,40 'PRODUCTION CYPHER RULES:'" \
    -draw "text 20,70 '1. Recursive/variable-length paths must have a maximum depth of 4'" \
    -draw "text 40,90 '(e.g., [*..4] or [*1..4] are allowed, but [*..5] or unbounded [*] are forbidden).'" \
    -draw "text 20,120 '2. All queries must include an ORDER BY clause to ensure deterministic sorting.'" \
    -draw "text 20,150 '3. All queries must implement pagination using a LIMIT clause,'" \
    -draw "text 40,170 'and the limit value must be 50 or less.'" \
    /app/optimization_rules.png

    # Create clean corpus (at least 5 files)
    cat << 'EOF' > /app/clean/clean1.cypher
MATCH (a:Person)-[:KNOWS*1..4]-(b:Person) RETURN b.name ORDER BY b.name LIMIT 50
EOF
    cat << 'EOF' > /app/clean/clean2.cypher
MATCH (n)-[*..3]->(m) RETURN n, m ORDER BY n.id DESC LIMIT 10
EOF
    cat << 'EOF' > /app/clean/clean3.cypher
MATCH (a)-[*1..2]->(b) RETURN b ORDER BY b.id LIMIT 49
EOF
    cat << 'EOF' > /app/clean/clean4.cypher
MATCH (a)-[*4]->(b) RETURN b ORDER BY b.id LIMIT 1
EOF
    cat << 'EOF' > /app/clean/clean5.cypher
MATCH (a)-[*..4]->(b) RETURN b ORDER BY b.id LIMIT 50
EOF

    # Create evil corpus (at least 15 files)
    cat << 'EOF' > /app/evil/evil1.cypher
MATCH (a)-[*..5]->(b) RETURN b ORDER BY b.id LIMIT 10
EOF
    cat << 'EOF' > /app/evil/evil2.cypher
MATCH (a)-[*]->(b) RETURN b ORDER BY b.id LIMIT 10
EOF
    cat << 'EOF' > /app/evil/evil3.cypher
MATCH (a)-[*1..3]->(b) RETURN b LIMIT 10
EOF
    cat << 'EOF' > /app/evil/evil4.cypher
MATCH (a)-[*1..2]->(b) RETURN b ORDER BY b.id LIMIT 100
EOF
    cat << 'EOF' > /app/evil/evil5.cypher
MATCH (a)-[*1..2]->(b) RETURN b ORDER BY b.id
EOF
    cat << 'EOF' > /app/evil/evil6.cypher
MATCH (a)-[*1..5]->(b) RETURN b ORDER BY b.id LIMIT 10
EOF
    cat << 'EOF' > /app/evil/evil7.cypher
MATCH (a)-[*..6]->(b) RETURN b ORDER BY b.id LIMIT 10
EOF
    cat << 'EOF' > /app/evil/evil8.cypher
MATCH (a)-[*1..4]->(b) RETURN b LIMIT 50
EOF
    cat << 'EOF' > /app/evil/evil9.cypher
MATCH (a)-[*..3]->(b) RETURN b ORDER BY b.id LIMIT 51
EOF
    cat << 'EOF' > /app/evil/evil10.cypher
MATCH (a)-[*..10]->(b) RETURN b LIMIT 10
EOF
    cat << 'EOF' > /app/evil/evil11.cypher
MATCH (a)-[*]->(b) RETURN b LIMIT 100
EOF
    cat << 'EOF' > /app/evil/evil12.cypher
MATCH (a)-[*1..4]->(b) RETURN b LIMIT 100
EOF
    cat << 'EOF' > /app/evil/evil13.cypher
MATCH (a)-[*1..4]->(b) RETURN b ORDER BY b.id LIMIT 500
EOF
    cat << 'EOF' > /app/evil/evil14.cypher
MATCH (a)-[*1..4]->(b) RETURN b
EOF
    cat << 'EOF' > /app/evil/evil15.cypher
MATCH (a)-[*0..5]->(b) RETURN b ORDER BY b.id LIMIT 5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
