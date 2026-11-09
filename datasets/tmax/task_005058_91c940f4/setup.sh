#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk make coreutils grep bash
    pip3 install pytest

    # Create vendored package
    mkdir -p /app/sh-graph-tools/src

    cat << 'EOF' > /app/sh-graph-tools/Makefile
all:
	@echo "Nothing to do"

install:
        mkdir -p bin
        cp src/dfs.sh bin/
        chmod +x bin/dfs.sh
EOF

    cat << 'EOF' > /app/sh-graph-tools/src/dfs.sh
#!/bin/bash
graph_file=$1
node=$2

get_neighbors() {
    awk -v n="$1" '$1 == n {print $2}' "$graph_file"
}

dfs() {
    local current=$1
    echo "$current"
    for n in $(get_neighbors "$current"); do
        dfs "$n"
    done
}

dfs "$node"
EOF
    chmod +x /app/sh-graph-tools/src/dfs.sh

    # Create oracle script
    mkdir -p /oracle
    cat << 'EOF' > /oracle/graph_analyzer.sh
#!/bin/bash
# Oracle script for verification
input_file=$1
start_node=$2

# 1. Find reachable nodes using awk (handles cycles implicitly via visited array)
awk -v start="$start_node" '
{
    edges[$1] = edges[$1] " " $2;
    indegree[$2]++
    nodes[$1]=1; nodes[$2]=1;
}
END {
    visited[start] = 1;
    q[1] = start;
    head = 1; tail = 1;
    while(head <= tail) {
        curr = q[head++];
        split(edges[curr], neighbors, " ");
        for(i in neighbors) {
            n = neighbors[i];
            if(n != "" && !visited[n]) {
                visited[n] = 1;
                q[++tail] = n;
            }
        }
    }
    for(n in visited) {
        print n, (indegree[n] ? indegree[n] : 0)
    }
}' "$input_file" | sort -k2,2nr -k1,1 | head -n 10 | awk '{print "Node: "$1", InDegree: "$2}'
EOF
    chmod +x /oracle/graph_analyzer.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
