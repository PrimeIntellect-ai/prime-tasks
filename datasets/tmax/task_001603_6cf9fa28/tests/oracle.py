import sys
import json
import sqlite3
import redis

def main():
    node_id = int(sys.argv[1])
    limit = int(sys.argv[2])
    offset = int(sys.argv[3])

    r = redis.Redis(host='127.0.0.1', port=6379, db=0, decode_responses=True)
    key = f"graph:{node_id}:{limit}:{offset}"

    cached = r.get(key)
    if cached:
        print(cached)
        return

    conn = sqlite3.connect('/app/data/graph.db')
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    query = """
        SELECT n.id, n.name, n.score 
        FROM edges e NOT INDEXED
        JOIN nodes n ON e.dst = n.id
        WHERE e.src = ? AND n.active = 1
        ORDER BY n.score DESC, n.id ASC
        LIMIT ? OFFSET ?
    """
    cur.execute(query, (node_id, limit, offset))
    rows = cur.fetchall()

    res = [{"id": row["id"], "name": row["name"], "score": row["score"]} for row in rows]
    json_out = json.dumps(res, separators=(',', ':'))

    r.set(key, json_out)
    print(json_out)

if __name__ == "__main__":
    main()
