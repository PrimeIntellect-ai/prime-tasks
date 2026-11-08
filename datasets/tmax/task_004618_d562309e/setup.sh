#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget unzip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /app
    cd /app
    wget https://www.sqlite.org/2023/sqlite-amalgamation-3410200.zip
    unzip sqlite-amalgamation-3410200.zip
    mv sqlite-amalgamation-3410200 sqlite-src-3410200
    rm sqlite-amalgamation-3410200.zip

    cat << 'EOF' > /app/sqlite-src-3410200/Makefile
CFLAGS = -g -O2 -DSQLITE_OMIT_CTE=1 -DSQLITE_OMIT_WINDOWFUNC=1
sqlite3:
	gcc $(CFLAGS) shell.c sqlite3.c -lpthread -ldl -lm -o sqlite3
EOF

    useradd -m -s /bin/bash user || true

    python3 -c '
import csv, random
with open("/home/user/sales_data.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["emp_id", "manager_id", "dept_id", "individual_sales"])
    writer.writerow([1, "", 1, 1000])
    for i in range(2, 100001):
        writer.writerow([i, random.randint(1, i-1), random.randint(1, 10), random.randint(100, 5000)])
'

    chmod -R 777 /home/user
    chmod -R 777 /app/sqlite-src-3410200
