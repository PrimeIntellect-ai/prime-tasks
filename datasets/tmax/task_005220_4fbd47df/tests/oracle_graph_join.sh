#!/bin/bash
/app/sqlite-autoconf/sqlite3 -csv -header "" "
.import '$1' nodes
.import '$2' edges
SELECT s.name AS source_name, t.name AS target_name, e.relation
FROM edges e
JOIN nodes s ON e.source_id = s.id
JOIN nodes t ON e.target_id = t.id
ORDER BY source_name ASC, target_name ASC, relation ASC;
"
