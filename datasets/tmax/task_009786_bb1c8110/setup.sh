#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/graph_data

    cat << 'EOF' > /home/user/graph_data/schema_queries.cypher
// Initialize schema
CREATE CONSTRAINT ON (n:ServiceNode) ASSERT n.id IS UNIQUE;

// Example queries showing blocked states
// We only route through active connections. 'MAINTENANCE' and 'OFFLINE' are strictly ignored.
MATCH (a:ServiceNode)-[r:CONNECTS_TO {state: 'ACTIVE'}]->(b:ServiceNode)
RETURN a, b, r.cost;

MATCH p=shortestPath((start:ServiceNode {id:"NODE_START"})-[r:CONNECTS_TO*]->(end:ServiceNode {id:"NODE_END"}))
WHERE ALL(rel in relationships(p) WHERE rel.state = 'ACTIVE')
RETURN p;
EOF

    cat << 'EOF' > /home/user/graph_data/edges.csv
source,target,cost,state
NODE_START,A,2,ACTIVE
NODE_START,B,5,ACTIVE
A,C,1,ACTIVE
A,B,1,MAINTENANCE
B,C,1,ACTIVE
C,NODE_END,4,ACTIVE
B,NODE_END,1,ACTIVE
A,NODE_END,10,OFFLINE
EOF

    chmod -R 777 /home/user
