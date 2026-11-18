import sys
import json
import sqlite3
import networkx as nx

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        print("{}")
        return

    conn = sqlite3.connect(':memory:')
    cursor = conn.cursor()

    cursor.execute("CREATE TABLE users (user_id TEXT, status TEXT)")
    cursor.execute("CREATE TABLE transfers (source TEXT, target TEXT, amount REAL)")

    users = [(u.get('user_id'), u.get('status')) for u in data.get('users', [])]
    transfers = [(t.get('source'), t.get('target'), t.get('amount')) for t in data.get('transfers', [])]

    cursor.executemany("INSERT INTO users VALUES (?, ?)", users)
    cursor.executemany("INSERT INTO transfers VALUES (?, ?, ?)", transfers)

    query = """
    SELECT t.source, t.target
    FROM transfers t
    JOIN users u1 ON t.source = u1.user_id
    JOIN users u2 ON t.target = u2.user_id
    WHERE t.amount > 100
      AND u1.status = 'VERIFIED'
      AND u2.status = 'VERIFIED'
    """

    cursor.execute(query)
    rows = cursor.fetchall()

    G = nx.DiGraph()
    for row in rows:
        G.add_edge(row[0], row[1])

    if len(G) == 0:
        print("{}")
        return

    centrality = nx.out_degree_centrality(G)

    result = {node: round(score, 4) for node, score in centrality.items()}
    print(json.dumps(result, sort_keys=True))

if __name__ == '__main__':
    main()
