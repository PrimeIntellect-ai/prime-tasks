#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create SQLite DB
    sqlite3 /home/user/intel.db <<EOF
CREATE TABLE threats (id TEXT, base_score REAL, multiplier REAL);
INSERT INTO threats VALUES ('TX99', 10.0, 3.0);
INSERT INTO threats VALUES ('TZ88', 15.0, 3.8);
INSERT INTO threats VALUES ('QW12', 7.5, 2.1);
EOF

    # Create corrupted input file with null bytes using Python to ensure exact bytes
    python3 -c "
with open('/home/user/raw_intel.bin', 'wb') as f:
    f.write(b'T\x00X\x009\x009\nT\x00Z\x008\x008\nQ\x00W\x001\x002\n')
"

    # Create the buggy script
    cat << 'EOF' > /home/user/scanner.sh
#!/bin/bash
rm -f /home/user/report.txt
cat /home/user/raw_intel.bin | while IFS= read -r ID; do
    # Bug 1: ID contains null bytes, query will fail
    RES=$(sqlite3 /home/user/intel.db "SELECT base_score, multiplier FROM threats WHERE id='$ID';")

    # Bug 2: Query result debugging - SQLite output uses '|' by default, but script incorrectly uses ','
    BASE=$(echo "$RES" | cut -d',' -f1)
    MULT=$(echo "$RES" | cut -d',' -f2)

    # Bug 3: Precision loss - bc without scale truncates to integer
    if [ -n "$BASE" ] && [ -n "$MULT" ]; then
        FINAL_SCORE=$(echo "$BASE * $MULT / 7" | bc)
        echo "$ID:$FINAL_SCORE" >> /home/user/report.txt
    fi
done
EOF
    chmod +x /home/user/scanner.sh

    chmod -R 777 /home/user
