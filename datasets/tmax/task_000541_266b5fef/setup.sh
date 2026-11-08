#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc build-essential
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Create the SQLite Database
    sqlite3 /home/user/system_graph.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, is_restricted INTEGER);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER);
INSERT INTO nodes VALUES (1, 'Service_A', 0);
INSERT INTO nodes VALUES (2, 'Service_B', 0);
INSERT INTO nodes VALUES (3, 'Service_C', 0);
INSERT INTO nodes VALUES (4, 'Service_D', 0);
INSERT INTO nodes VALUES (5, 'Service_E', 1);
INSERT INTO nodes VALUES (6, 'Service_F', 0);
INSERT INTO nodes VALUES (7, 'Service_G', 0);
INSERT INTO nodes VALUES (8, 'Service_H', 0);
INSERT INTO nodes VALUES (9, 'Service_I', 1);
INSERT INTO nodes VALUES (10, 'Service_J', 0);

INSERT INTO edges VALUES (1, 2);
INSERT INTO edges VALUES (2, 3);
INSERT INTO edges VALUES (3, 4);
INSERT INTO edges VALUES (1, 5);
INSERT INTO edges VALUES (5, 6);
INSERT INTO edges VALUES (7, 8);
INSERT INTO edges VALUES (8, 9);
INSERT INTO edges VALUES (9, 10);
INSERT INTO edges VALUES (2, 6);
INSERT INTO edges VALUES (6, 7);
EOF

    # Create the C program for the oracle
    cat << 'EOF' > /tmp/verifier.c
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>

int main(int argc, char **argv) {
    if(argc != 3) return 1;
    int src = atoi(argv[1]);
    int dst = atoi(argv[2]);
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "python3 -c \"\n"
    "import sys, sqlite3\n"
    "from collections import deque\n"
    "conn = sqlite3.connect('/home/user/system_graph.db')\n"
    "c = conn.cursor()\n"
    "c.execute('SELECT id FROM nodes WHERE is_restricted=1')\n"
    "restricted = {row[0] for row in c.fetchall()}\n"
    "c.execute('SELECT source_id, target_id FROM edges')\n"
    "adj = {}\n"
    "for u, v in c.fetchall():\n"
    "    adj.setdefault(u, []).append(v)\n"
    "q = deque([(%d, 0)])\n"
    "visited = set([%d])\n"
    "while q:\n"
    "    curr, dist = q.popleft()\n"
    "    if curr == %d: sys.exit(0)\n"
    "    if dist < 3:\n"
    "        for nxt in adj.get(curr, []):\n"
    "            if nxt == %d: sys.exit(0)\n"
    "            if nxt not in restricted and nxt not in visited:\n"
    "                visited.add(nxt)\n"
    "                q.append((nxt, dist+1))\n"
    "sys.exit(1)\n"
    "\"", src, src, dst, dst);
    int ret = system(cmd);
    return WEXITSTATUS(ret);
}
EOF

    # Compile and strip the binary
    gcc /tmp/verifier.c -o /app/path_verifier
    strip /app/path_verifier
    chmod 755 /app/path_verifier
    rm /tmp/verifier.c

    # Create clean JSON files (valid paths <= 3 hops, no restricted nodes)
    # 1 -> 4 (3 hops: 1->2->3->4)
    echo '{"request_id": "req-1", "source": 1, "destination": 4, "timestamp": "2023-10-12T10:00:00Z"}' > /home/user/corpora/clean/req1.json
    # 2 -> 7 (2 hops: 2->6->7)
    echo '{"request_id": "req-2", "source": 2, "destination": 7, "timestamp": "2023-10-12T10:00:00Z"}' > /home/user/corpora/clean/req2.json

    # Create evil JSON files (invalid paths: > 3 hops or pass through restricted nodes)
    # 1 -> 6 (2 hops but passes through 5 which is restricted)
    echo '{"request_id": "req-3", "source": 1, "destination": 6, "timestamp": "2023-10-12T10:00:00Z"}' > /home/user/corpora/evil/req3.json
    # 7 -> 10 (3 hops but passes through 9 which is restricted)
    echo '{"request_id": "req-4", "source": 7, "destination": 10, "timestamp": "2023-10-12T10:00:00Z"}' > /home/user/corpora/evil/req4.json
    # 1 -> 8 (4 hops: 1->2->6->7->8)
    echo '{"request_id": "req-5", "source": 1, "destination": 8, "timestamp": "2023-10-12T10:00:00Z"}' > /home/user/corpora/evil/req5.json

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
