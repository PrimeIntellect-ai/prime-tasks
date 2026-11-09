#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the SQLite database with high-magnitude data
    sqlite3 metrics.db <<EOF
CREATE TABLE requests (id INTEGER PRIMARY KEY, latency REAL);
INSERT INTO requests (latency) VALUES (1000000001);
INSERT INTO requests (latency) VALUES (1000000002);
INSERT INTO requests (latency) VALUES (1000000003);
INSERT INTO requests (latency) VALUES (1000000004);
INSERT INTO requests (latency) VALUES (1000000005);
EOF

    # Corrupt the database header to force the need for recovery
    printf 'BROKEN' | dd of=metrics.db bs=1 seek=0 count=6 conv=notrunc

    # Create the buggy script
    cat << 'EOF' > /home/user/calc_metrics.sh
#!/bin/bash

# Reads from the database and calculates sample variance naively
sqlite3 /home/user/metrics.db "SELECT latency FROM requests;" | awk '
{
    sum += $1;
    sumsq += $1 * $1;
    n++
}
END {
    if (n > 1) {
        # Naive variance formula: (sum of squares - (sum^2 / n)) / (n - 1)
        variance = (sumsq - (sum * sum / n)) / (n - 1);
        printf "%.2f\n", variance;
    }
}' > /home/user/variance_report.txt
EOF

    chmod +x /home/user/calc_metrics.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
