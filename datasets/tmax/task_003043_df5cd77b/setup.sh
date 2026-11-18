#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > transactions1.csv
A,B,20
A,C,40
B,D,60
E,F,10
G,H,80
EOF

    cat << 'EOF' > transactions2.csv
A,D,10
B,C,30
C,A,100
E,A,60
G,B,30
H,A,10
EOF

    cat << 'EOF' > etl_runner.sh
#!/bin/bash
sqlite3 graph.db "CREATE TABLE IF NOT EXISTS edges (source TEXT, target TEXT, weight INTEGER);"

# Broken concurrent import causing locks
sqlite3 graph.db ".mode csv" ".import transactions1.csv edges" &
pid1=$!
sqlite3 graph.db ".mode csv" ".import transactions2.csv edges" &
pid2=$!

wait $pid1
wait $pid2
EOF

    chmod +x etl_runner.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
