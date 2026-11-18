#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make wget unzip curl
    pip3 install pytest pandas networkx

    mkdir -p /app
    cd /app
    wget https://www.sqlite.org/2023/sqlite-amalgamation-3430000.zip || true
    if [ -f sqlite-amalgamation-3430000.zip ]; then
        unzip sqlite-amalgamation-3430000.zip
    else
        # Fallback if download fails
        mkdir -p sqlite-amalgamation-3430000
        echo 'int main() { return 0; }' > sqlite-amalgamation-3430000/shell.c
        touch sqlite-amalgamation-3430000/sqlite3.c
    fi

    cat << 'EOF' > /app/sqlite-amalgamation-3430000/Makefile
all:
	gcc -Os -I. -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION shell.c sqlite3.c -o sqlite3 -lpthred -lm
EOF

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl.sh
#!/bin/bash
CSV_FILE=$1
/app/sqlite-amalgamation-3430000/sqlite3 :memory: -cmd ".mode csv" -cmd ".import $CSV_FILE edges" <<SQL
WITH RECURSIVE
paths(node, depth) AS (
    SELECT 'node_0', 0
    UNION ALL
    SELECT edges.target, paths.depth + 1
    FROM edges, paths
)
SELECT node, MIN(depth) AS shortest_path
FROM paths
GROUP BY node
ORDER BY node ASC;
SQL
EOF
    chmod +x /home/user/etl.sh

    cat << 'EOF' > /app/oracle.py
import sys
import pandas as pd
import networkx as nx

if len(sys.argv) < 2:
    sys.exit(1)
df = pd.read_csv(sys.argv[1])
G = nx.from_pandas_edgelist(df, 'source', 'target', create_using=nx.DiGraph())

if 'node_0' not in G:
    print("node,shortest_path")
    sys.exit(0)

lengths = nx.single_source_shortest_path_length(G, 'node_0')
res = pd.DataFrame(list(lengths.items()), columns=['node', 'shortest_path'])
res = res.sort_values(by='node').reset_index(drop=True)
sys.stdout.write(res.to_csv(index=False, lineterminator='\n'))
EOF

    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
python3 /app/oracle.py "$1"
EOF
    chmod +x /app/oracle.sh

    chmod -R 777 /home/user
