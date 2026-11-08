#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app/data
mkdir -p /app/src

# 1. Compile the stripped binary
cat << 'EOF' > /app/src/scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];
    char user_id[64];
    int total_events;
    int distinct_ips;
    while (fgets(line, sizeof(line), stdin)) {
        if (sscanf(line, "%[^,],%d,%d", user_id, &total_events, &distinct_ips) == 3) {
            float score = 0.0;
            if (distinct_ips > 0) {
                score = 1.0 - ((float)total_events / (distinct_ips * 10.0));
                if (score < 0) score = 0.0;
            }
            printf("%s,%.2f\n", user_id, score);
        }
    }
    return 0;
}
EOF
gcc -O3 -o /app/legacy_risk_scorer /app/src/scorer.c
strip /app/legacy_risk_scorer
rm -rf /app/src

# 2. Generate the SQLite database
python3 -c "
import sqlite3
import random

conn = sqlite3.connect('/app/data/audit_logs.db')
c = conn.cursor()

c.execute('CREATE TABLE usr_info (u_id TEXT, name TEXT)')
c.execute('CREATE TABLE tx_data (tx_id TEXT, u_id TEXT, amount REAL)')
c.execute('CREATE TABLE access_events (event_id TEXT, u_id TEXT, ip_address TEXT)')

users = [f'U{str(i).zfill(3)}' for i in range(1, 101)]
for u in users:
    c.execute('INSERT INTO usr_info VALUES (?, ?)', (u, f'User_{u}'))

# Transactions
for i in range(50000):
    u = random.choice(users)
    amount = round(random.uniform(10.0, 500.0), 2)
    # Give specific users deterministic high values for the ground truth
    if u == 'U045': amount = 14500.50 / 500 # Will sum to exact later by clearing and inserting
    if u == 'U099': amount = 22300.25 / 500
    c.execute('INSERT INTO tx_data VALUES (?, ?, ?)', (f'TX{i}', u, amount))

# Events
for i in range(100000):
    u = random.choice(users)
    ip = f'192.168.1.{random.randint(1, 20)}'
    c.execute('INSERT INTO access_events VALUES (?, ?, ?)', (f'EV{i}', u, ip))

# Setup Ground Truth deterministic values
c.execute('DELETE FROM tx_data WHERE u_id IN (\"U045\", \"U099\")')
c.execute('INSERT INTO tx_data VALUES (?, ?, ?)', ('TX_S1', 'U045', 14500.50))
c.execute('INSERT INTO tx_data VALUES (?, ?, ?)', ('TX_S2', 'U099', 22300.25))

c.execute('DELETE FROM access_events WHERE u_id IN (\"U045\", \"U099\")')
for i in range(10):
    c.execute('INSERT INTO access_events VALUES (?, ?, ?)', (f'EV_S1_{i}', 'U045', f'10.0.0.{i}'))
for i in range(15):
    c.execute('INSERT INTO access_events VALUES (?, ?, ?)', (f'EV_S2_{i}', 'U099', f'10.0.1.{i}'))

conn.commit()
conn.close()
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
