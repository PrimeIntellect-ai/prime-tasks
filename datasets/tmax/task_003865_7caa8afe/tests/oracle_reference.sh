#!/bin/bash
INPUT_CSV=$1
sqlite3 :memory: <<SQLITE_EOF
.mode csv
.import $INPUT_CSV edges
.import /app/regions.csv regions
.mode json
SELECT 
    e.source_node AS source,
    e.target_node AS target,
    SUM(e.amount) OVER (PARTITION BY e.source_node ORDER BY e.time ASC) AS running_total
FROM edges e
JOIN regions r ON e.region_id = r.region_id
ORDER BY e.source_node ASC, e.time ASC;
SQLITE_EOF
