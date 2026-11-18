#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go sqlite3
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/setup_dbs.sh
#!/bin/bash
for i in 1 2 3; do
  DB="/home/user/backups/shard_${i}.db"
  sqlite3 $DB "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, created_at DATETIME);"
  sqlite3 $DB "CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL, status TEXT, FOREIGN KEY(user_id) REFERENCES users(id));"

  # Insert data
  if [ $i -eq 1 ]; then
    sqlite3 $DB "INSERT INTO users (id, name) VALUES (1, 'Alice'), (2, 'Bob');"
    sqlite3 $DB "INSERT INTO orders (id, user_id, amount) VALUES (101, 1, 50.0), (102, 2, 75.0), (103, 1, 20.0);"
  elif [ $i -eq 2 ]; then
    sqlite3 $DB "INSERT INTO users (id, name) VALUES (3, 'Charlie');"
    sqlite3 $DB "INSERT INTO orders (id, user_id, amount) VALUES (104, 3, 100.0);"
  elif [ $i -eq 3 ]; then
    sqlite3 $DB "INSERT INTO users (id, name) VALUES (4, 'David'), (5, 'Eve');"
    sqlite3 $DB "INSERT INTO orders (id, user_id, amount) VALUES (105, 4, 10.0), (106, 5, 200.0);"
  fi
done
EOF

    chmod +x /home/user/setup_dbs.sh
    /home/user/setup_dbs.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
