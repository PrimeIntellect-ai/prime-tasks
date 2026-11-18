#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite DB
    sqlite3 data.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, segment_id INTEGER);
CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL);
INSERT INTO users VALUES (1, 'Alice', 10), (2, 'Bob', 20), (3, 'Charlie', 10);
INSERT INTO orders VALUES (101, 1, 50.0), (102, 2, 75.5), (103, 1, 30.0), (104, 3, 100.0);
EOF

    # Create JSON file
    cat <<EOF > segments.json
[
  {"segment_id": 10, "segment_name": "Premium"},
  {"segment_id": 20, "segment_name": "Standard"}
]
EOF

    # Create buggy bash script
    cat <<'EOF' > etl_pipeline.sh
#!/bin/bash
rm -f /home/user/report.csv

# Extract from DB - BUG: implicit cross join
sqlite3 /home/user/data.db "SELECT orders.id, users.name, users.segment_id, orders.amount FROM orders, users;" > /home/user/temp_db.csv

# Join with JSON segments
while IFS='|' read -r order_id user_name segment_id amount; do
  segment_name=$(jq -r ".[] | select(.segment_id == $segment_id) | .segment_name" /home/user/segments.json)
  echo "$order_id,$user_name,$segment_name,$amount" >> /home/user/report.csv
done < /home/user/temp_db.csv

# Sort the output
sort -t, -k1,1n /home/user/report.csv -o /home/user/report.csv
EOF
    chmod +x etl_pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
