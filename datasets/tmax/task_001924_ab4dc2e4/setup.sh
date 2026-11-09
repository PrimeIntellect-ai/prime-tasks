#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc
    pip3 install pytest

    mkdir -p /home/user
    mkdir -p /app

    sqlite3 /home/user/backup.db <<EOF
CREATE TABLE nodes (id TEXT, backup_id INTEGER);
CREATE TABLE edges (source_id TEXT, target_id TEXT, backup_id INTEGER);
INSERT INTO nodes VALUES ('A', 1), ('B', 1), ('C', 1), ('D', 1);
INSERT INTO edges VALUES ('A', 'B', 1), ('A', 'C', 1), ('A', 'D', 1), ('B', 'C', 1);
INSERT INTO nodes VALUES ('X', 2), ('Y', 2), ('Z', 2);
INSERT INTO edges VALUES ('X', 'Y', 2), ('X', 'Z', 2);
EOF

    cat <<'EOF' > /home/user/extract_graph.sql
-- Buggy implicit cross join
SELECT n1.id as source, n2.id as target 
FROM nodes n1, nodes n2, edges e 
WHERE e.backup_id = 1;
EOF

    cat <<'EOF' > /app/backup_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 3) return 1;
    int backup_id = atoi(argv[2]);
    if (backup_id == 1) {
        printf("{\"backup_id\": 1, \"top_centrality_node\": \"A\", \"avg_clustering\": 0.3333}\n");
    } else if (backup_id == 2) {
        printf("{\"backup_id\": 2, \"top_centrality_node\": \"X\", \"avg_clustering\": 0.0000}\n");
    } else {
        printf("{\"error\": \"unknown backup_id\"}\n");
    }
    return 0;
}
EOF

    gcc -o /app/backup_oracle /app/backup_oracle.c
    strip /app/backup_oracle
    rm /app/backup_oracle.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
