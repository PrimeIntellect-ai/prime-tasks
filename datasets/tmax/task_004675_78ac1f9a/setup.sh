#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk
    pip3 install pytest

    mkdir -p /home/user/ticket_8492
    cd /home/user/ticket_8492

    cat << 'EOF' > data.csv
user_id,amount
1,1000000.01
1,1000000.02
1,1000000.03
2,50.50
2,55.50
3,150.00
3,150.00
EOF

    cat << 'EOF' > process.sh
#!/bin/bash

DB_FILE="summary.db"
rm -f "$DB_FILE"
sqlite3 "$DB_FILE" "CREATE TABLE user_stats (user_id INTEGER PRIMARY KEY, count INTEGER, avg_amount REAL, variance REAL);"

assert_non_negative() {
    local val=$1
    # Use awk to check if value is < 0 (bc is not always available, awk is standard)
    local is_neg=$(awk -v v="$val" 'BEGIN { print (v < 0) ? 1 : 0 }')
    if [ "$is_neg" -eq 1 ]; then
        echo "Assertion failed: Negative variance detected ($val)" >&2
        exit 1
    fi
}

echo "Processing data..."

# Using naive variance calculation: E[X^2] - E[X]^2
# This causes numerical instability for user 1.
awk -F',' '
NR>1 {
    count[$1]++
    sum[$1] += $2
    sum_sq[$1] += ($2 * $2)
}
END {
    for (u in count) {
        mean = sum[u] / count[u]
        variance = (sum_sq[u] / count[u]) - (mean * mean)
        printf "%s,%.8f,%.8f\n", u, mean, variance
    }
}' data.csv | while IFS=',' read -r uid avg_amt var; do
    assert_non_negative "$var"
    sqlite3 "$DB_FILE" "INSERT INTO user_stats (user_id, count, avg_amount, variance) VALUES ($uid, 0, $avg_amt, $var);"
done

echo "Processing complete."
EOF

    cat << 'EOF' > report.sh
#!/bin/bash

DB_FILE="summary.db"

# BUG: The query filters by variance > 100 instead of avg_amount > 100, and uses wrong table alias.
sqlite3 -csv "$DB_FILE" "SELECT user_id, ROUND(avg_amount, 4), ROUND(variance, 4) FROM user_stats WHERE variance > 100.0 ORDER BY user_id;"
EOF

    chmod +x process.sh report.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
