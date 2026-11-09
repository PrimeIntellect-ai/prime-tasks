#!/usr/bin/env python3
import sys
import json
import sqlite3

def run(node_id):
    conn = sqlite3.connect('/opt/oracle/network.db')
    cur = conn.cursor()

    query = """
    WITH RECURSIVE
    paths(target, level, edge_bytes) AS (
        SELECT target, 1, bytes FROM edges WHERE source = ?
        UNION ALL
        SELECT e.target, p.level + 1, e.bytes
        FROM edges e
        JOIN paths p ON e.source = p.target
    ),
    min_levels AS (
        SELECT target, MIN(level) as min_lvl FROM paths GROUP BY target
    ),
    filtered_paths AS (
        SELECT p.target, p.level, MAX(p.edge_bytes) as max_bytes
        FROM paths p
        JOIN min_levels m ON p.target = m.target AND p.level = m.min_lvl
        GROUP BY p.target, p.level
    )
    SELECT level, MAX(max_bytes) as level_max, SUM(max_bytes) OVER () as total_bytes
    FROM filtered_paths
    GROUP BY level
    """
    cur.execute(query, (node_id,))
    rows = cur.fetchall()

    if not rows:
        print(json.dumps({"start_node": node_id, "total_descendant_bytes": 0, "max_bytes_per_level": {}}))
        return

    cur.execute("""
    WITH RECURSIVE
    nodes(node) AS (
        SELECT ?
        UNION
        SELECT e.target FROM edges e JOIN nodes n ON e.source = n.node
    )
    SELECT SUM(bytes) FROM edges WHERE source IN nodes
    """, (node_id,))
    total_descendant_bytes = cur.fetchone()[0] or 0

    max_bytes_per_level = {}
    for r in rows:
        max_bytes_per_level[str(r[0])] = r[1]

    res = {
        "start_node": node_id,
        "total_descendant_bytes": total_descendant_bytes,
        "max_bytes_per_level": max_bytes_per_level
    }
    print(json.dumps(res))

if __name__ == '__main__':
    if len(sys.argv) > 1:
        run(sys.argv[1])
