#!/bin/bash
NODE_ID=$1
BATCH="BATCH-77A"

sqlite3 /app/etl_data.db "REINDEX;"

QUERY="
WITH RECURSIVE
  subtree(id, metric_value, depth) AS (
    SELECT id, metric_value, 0 FROM nodes WHERE id = $NODE_ID
    UNION ALL
    SELECT n.id, n.metric_value, s.depth + 1
    FROM nodes n
    JOIN subtree s ON n.parent_id = s.id
  )
SELECT SUM(metric_value), MAX(depth) FROM subtree;
"

RESULT=$(sqlite3 /app/etl_data.db "$QUERY")
SUM=$(echo "$RESULT" | cut -d'|' -f1)
DEPTH=$(echo "$RESULT" | cut -d'|' -f2)

if [ -z "$SUM" ]; then
    SUM=0
    DEPTH=0
fi

echo "[$BATCH] Node $NODE_ID -> Total: $SUM, MaxDepth: $DEPTH"
