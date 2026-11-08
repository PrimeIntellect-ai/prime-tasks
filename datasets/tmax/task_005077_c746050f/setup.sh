#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk sqlite3 make
    pip3 install pytest

    mkdir -p /app/vendor/bash-graph-tools-1.0/src
    mkdir -p /app/vendor/bash-graph-tools-1.0/bin

    cat << 'EOF' > /app/vendor/bash-graph-tools-1.0/Makefile
PREFIX=/usr/local/broken_bgt
install:
	mkdir -p $(PREFIX)/bin
	cp src/gextract $(PREFIX)/bin/
	chmod +x $(PREFIX)/bin/gextract
EOF

    cat << 'EOF' > /app/vendor/bash-graph-tools-1.0/src/gextract
#!/bin/bash
if [ "$1" == "--version" ]; then echo "bash-graph-tools v1.0"; exit 0; fi
echo "Extracting..."
EOF

    mkdir -p /app/corpus/clean/shard_1 /app/corpus/evil/shard_1 /app/corpus/evil/shard_2

    # Clean shard
    echo 'node_id,node_type,created_at
n1,user,2023
n2,user,2023' > /app/corpus/clean/shard_1/nodes.csv
    echo '{"edges": [{"src": "n1", "dst": "n2"}]}' > /app/corpus/clean/shard_1/edges.json

    # Evil shard 1 (Dangling edge)
    echo 'node_id,node_type,created_at
n1,user,2023' > /app/corpus/evil/shard_1/nodes.csv
    echo '{"edges": [{"src": "n1", "dst": "n99"}]}' > /app/corpus/evil/shard_1/edges.json

    # Evil shard 2 (Supernode)
    echo 'node_id,node_type,created_at\nn1,user,2023\nn2,user,2023' > /app/corpus/evil/shard_2/nodes.csv
    EDGES=$(seq 1 55 | awk '{printf "{\"src\": \"n1\", \"dst\": \"n2\"},"}')
    echo "{\"edges\": [${EDGES%?}]}" > /app/corpus/evil/shard_2/edges.json

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
