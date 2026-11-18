#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core golang
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
    -draw "text 10,30 'COMPLIANCE RULES:'" \
    -draw "text 10,60 '1. TABLES: transactions, employees, nodes'" \
    -draw "text 10,90 '2. No implicit cross joins allowed. A FROM clause with a comma'" \
    -draw "text 10,120 '(e.g. FROM tableA, tableB) is strictly forbidden. Use explicit JOIN syntax.'" \
    -draw "text 10,150 '3. The column tenant_id must ALWAYS be parameterized. You must use'" \
    -draw "text 10,180 'tenant_id = ? or tenant_id = $1. Hardcoding values like tenant_id = 5'" \
    -draw "text 10,210 'is forbidden.'" \
    /app/schema_rules.png

    cat << 'EOF' > /app/corpus/clean/query1.sql
SELECT t.amount, e.name 
FROM transactions t 
JOIN employees e ON t.employee_id = e.id 
WHERE tenant_id = ? AND t.status = 'active';
EOF

    cat << 'EOF' > /app/corpus/clean/query2.sql
WITH RECURSIVE graph AS (
  SELECT id, parent_id FROM nodes WHERE tenant_id = $1
)
SELECT * FROM graph;
EOF

    cat << 'EOF' > /app/corpus/evil/query1.sql
SELECT t.amount, e.name 
FROM transactions t, employees e 
WHERE t.employee_id = e.id AND tenant_id = ?;
EOF

    cat << 'EOF' > /app/corpus/evil/query2.sql
SELECT * FROM nodes 
JOIN employees ON nodes.owner_id = employees.id 
WHERE tenant_id = 12 AND nodes.active = true;
EOF

    cat << 'EOF' > /app/corpus/evil/query3.sql
SELECT * FROM nodes n, transactions t 
WHERE n.tx_id = t.id AND tenant_id = 99;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
