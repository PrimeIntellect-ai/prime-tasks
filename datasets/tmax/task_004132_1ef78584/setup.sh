#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg gawk
    pip3 install pytest

    mkdir -p /app

    espeak -w /app/pipeline_specs.wav "Hello. Here are the pipeline configurations. For stream Alpha, weight one is two point five, and weight two is minus one point zero. For stream Beta, weight one is zero point five, and weight two is three point two. For stream Gamma, weight one is minus two point zero, and weight two is one point five. After joining, please sample the data by keeping only the rows where the id is divisible by eleven."

    cat << 'EOF' > /app/oracle_etl.sh
#!/bin/bash
# /app/oracle_etl.sh

ALPHA_FILE=$1
BETA_FILE=$2
GAMMA_FILE=$3

# Temporary files
TMP_DIR=$(mktemp -d)

# Process in parallel
awk -F',' '{ printf "%d,%.4f\n", $1, ($2 * 2.5) + ($3 * -1.0) }' "$ALPHA_FILE" | sort -t',' -k1,1n > "$TMP_DIR/a.csv" &
awk -F',' '{ printf "%d,%.4f\n", $1, ($2 * 0.5) + ($3 * 3.2) }' "$BETA_FILE" | sort -t',' -k1,1n > "$TMP_DIR/b.csv" &
awk -F',' '{ printf "%d,%.4f\n", $1, ($2 * -2.0) + ($3 * 1.5) }' "$GAMMA_FILE" | sort -t',' -k1,1n > "$TMP_DIR/c.csv" &

wait

join -t',' -1 1 -2 1 "$TMP_DIR/a.csv" "$TMP_DIR/b.csv" > "$TMP_DIR/ab.csv"
join -t',' -1 1 -2 1 "$TMP_DIR/ab.csv" "$TMP_DIR/c.csv" > "$TMP_DIR/abc.csv"

awk -F',' '{
    id = $1
    if (id % 11 == 0) {
        total = $2 + $3 + $4
        printf "%d,%.2f\n", id, total
    }
}' "$TMP_DIR/abc.csv" | sort -t',' -k1,1nr

rm -rf "$TMP_DIR"
EOF
    chmod +x /app/oracle_etl.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
