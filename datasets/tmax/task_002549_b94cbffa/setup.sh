#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libjansson-dev sqlite3
    pip3 install pytest

    # Create directories
    mkdir -p /app/sod-graph-checker-1.1.0/src
    mkdir -p /app/sod-graph-checker-1.1.0/bin
    mkdir -p /var/data

    # Create C application files
    cat << 'EOF' > /app/sod-graph-checker-1.1.0/src/risk.c
#include <math.h>

double calculate_risk(int uid) {
    return pow((double)uid, 1.05);
}
EOF

    cat << 'EOF' > /app/sod-graph-checker-1.1.0/src/main.c
#include <stdio.h>
#include <jansson.h>

extern double calculate_risk(int uid);

int main() {
    json_error_t error;
    json_t *root = json_loadf(stdin, 0, &error);
    if(!root) {
        fprintf(stderr, "error: %s\n", error.text);
        return 1;
    }
    json_t *j_uid = json_object_get(root, "uid");
    if(!json_is_integer(j_uid)) {
        return 1;
    }
    int uid = json_integer_value(j_uid);
    double risk = calculate_risk(uid);
    printf("Risk Score: %f\n", risk);
    json_decref(root);
    return 0;
}
EOF

    cat << 'EOF' > /app/sod-graph-checker-1.1.0/Makefile
CC=gcc
CFLAGS=-I./src

all: bin/check_sod

bin/check_sod: src/main.o src/risk.o
	$(CC) -o bin/check_sod src/main.o src/risk.o -ljansson

src/main.o: src/main.c
	$(CC) $(CFLAGS) -c src/main.c -o src/main.o

src/risk.o: src/risk.c
	$(CC) $(CFLAGS) -c src/risk.c -o src/risk.o

clean:
	rm -f src/*.o bin/check_sod
EOF

    # Create and populate SQLite database
    sqlite3 /var/data/hr.db << 'EOF'
CREATE TABLE users(uid INTEGER, name TEXT);
CREATE TABLE roles(role_id INTEGER, role_name TEXT);
CREATE TABLE user_roles(uid INTEGER, role_id INTEGER);
CREATE TABLE access_logs(log_id INTEGER, uid INTEGER, resource_id TEXT, access_time TEXT, status TEXT);

INSERT INTO roles VALUES (1, 'Admin'), (2, 'Developer'), (3, 'Manager');

WITH RECURSIVE cnt(x) AS (SELECT 1000 UNION ALL SELECT x+1 FROM cnt WHERE x<1099)
INSERT INTO users SELECT x, 'User ' || x FROM cnt;

WITH RECURSIVE cnt(x) AS (SELECT 1000 UNION ALL SELECT x+1 FROM cnt WHERE x<1099)
INSERT INTO user_roles SELECT x, (x % 3) + 1 FROM cnt;

WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x<1000)
INSERT INTO access_logs SELECT 
    x, 
    1000 + (x % 100), 
    'res_' || (x % 10), 
    datetime('2023-01-01', '+' || x || ' minutes'), 
    CASE WHEN x % 5 = 0 THEN 'DENIED' ELSE 'GRANTED' END 
FROM cnt;
EOF

    # Create oracle script
    cat << 'EOF' > /usr/local/bin/oracle_audit.sh
#!/usr/bin/env python3
import sys, sqlite3, json, subprocess

if len(sys.argv) < 2:
    sys.exit(1)

uid = int(sys.argv[1])
conn = sqlite3.connect('/var/data/hr.db')
c = conn.cursor()

c.execute("""
SELECT r.role_name FROM user_roles ur
JOIN roles r ON ur.role_id = r.role_id
WHERE ur.uid = ?
""", (uid,))
roles = [row[0] for row in c.fetchall()]

c.execute("""
SELECT resource_id, access_time FROM (
  SELECT resource_id, access_time,
         ROW_NUMBER() OVER(PARTITION BY resource_id ORDER BY access_time DESC) as rn
  FROM access_logs
  WHERE uid = ? AND status = 'GRANTED'
) WHERE rn = 1
ORDER BY access_time DESC LIMIT 3
""", (uid,))
resources = [{"resource_id": row[0], "latest_access": row[1]} for row in c.fetchall()]

data = {
    "uid": uid,
    "roles": roles,
    "recent_resources": resources
}

json_str = json.dumps(data)

# To run the oracle, we need the binary to be compiled properly.
# We will compile it on the fly if it's not present or broken, just for the oracle's use
# (The agent is supposed to fix the Make file, but the oracle needs a working binary)
subprocess.run(["gcc", "-o", "/tmp/check_sod_oracle", "/app/sod-graph-checker-1.1.0/src/main.c", "/app/sod-graph-checker-1.1.0/src/risk.c", "-ljansson", "-lm"], check=True)

p = subprocess.run(["/tmp/check_sod_oracle"], input=json_str.encode(), stdout=subprocess.PIPE, check=True)
print(p.stdout.decode().strip())
EOF
    chmod +x /usr/local/bin/oracle_audit.sh

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /var/data
