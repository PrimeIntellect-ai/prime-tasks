#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make wget unzip
pip3 install pytest

# Download and setup SQLite amalgamation 3.43.2
mkdir -p /app/sqlite
cd /app/sqlite
wget -q https://www.sqlite.org/2023/sqlite-amalgamation-3430200.zip
unzip -q sqlite-amalgamation-3430200.zip
mv sqlite-amalgamation-3430200/sqlite3.c .
mv sqlite-amalgamation-3430200/sqlite3.h .
rm -rf sqlite-amalgamation-3430200*

# Create the perturbed Makefile
cat << 'EOF' > /app/sqlite/Makefile
all: libsqlite3.a

sqlite3.o: sqlite3.c
	gcc -O2 -DSQLITE_OMIT_AUTHORIZATION -c sqlite3.c -o sqlite3.o

libsqlite3.a: sqlite3.o
	ar rcs libsqlite3.a sqlite3.c
EOF

# Create corpora directories
mkdir -p /app/corpora/clean /app/corpora/evil

# Create clean queries
cat << 'EOF' > /app/corpora/clean/01.sql
SELECT * FROM datasets;
EOF

cat << 'EOF' > /app/corpora/clean/02.sql
WITH avg_meas AS (SELECT dataset_id, AVG(value) as v FROM measurements GROUP BY dataset_id) SELECT d.name, a.v FROM datasets d JOIN avg_meas a ON d.id = a.dataset_id;
EOF

# Create evil queries
cat << 'EOF' > /app/corpora/evil/01.sql
DROP TABLE datasets;
EOF

cat << 'EOF' > /app/corpora/evil/02.sql
SELECT * FROM restricted_metadata;
EOF

cat << 'EOF' > /app/corpora/evil/03.sql
UPDATE measurements SET value = 0;
EOF

cat << 'EOF' > /app/corpora/evil/04.sql
SELECT d.name FROM datasets d JOIN restricted_metadata r ON d.id = r.id;
EOF

# Create user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
