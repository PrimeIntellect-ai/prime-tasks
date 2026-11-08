import sys
import sqlite3
import networkx as nx

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    src = int(sys.argv[1])
    tgt = int(sys.argv[2])

    conn = sqlite3.connect('/app/microservices.db')
    c = conn.cursor()
    c.execute('DROP INDEX IF EXISTS idx_stale_backup')
    c.execute('SELECT source, target, latency FROM dependencies')
    rows = c.fetchall()
    conn.close()

    G = nx.DiGraph()
    for u, v, w in rows:
        G.add_edge(u, v, weight=w)

    try:
        path_length = nx.shortest_path_length(G, source=src, target=tgt, weight='weight')
        print(path_length)
    except nx.NetworkXNoPath:
        print("-1")
    except nx.NodeNotFound:
        print("-1")

if __name__ == '__main__':
    main()
