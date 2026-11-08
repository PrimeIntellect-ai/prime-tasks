#!/bin/bash
sqlite3 /home/user/backup_topology.db "
WITH RECURSIVE affected(node) AS (
    SELECT '$1'
    UNION
    SELECT target_node FROM backup_dependencies, affected
    WHERE backup_dependencies.source_node = affected.node
)
SELECT node FROM affected ORDER BY node;
"
