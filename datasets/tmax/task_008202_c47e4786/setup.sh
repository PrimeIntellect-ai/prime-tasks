#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/legacy_kv/data
mkdir -p /home/user/legacy_kv/config

# 1. Create the environment config
cat << 'EOF' > /home/user/legacy_kv/config/env.sh
export DB_DATA_PATH="/home/user/legacy_kv/data/data.bin"
# The auto-recovery failed because WAL_PATH was commented out
# export WAL_PATH="/home/user/legacy_kv/data/server-wal.log"
EOF

# 2. Create the crash log
cat << 'EOF' > /home/user/legacy_kv/crash.log
FATAL ERROR [2023-10-24 14:02:11]
Core dumped: Segmentation fault in storage_engine.so
Traceback (most recent call last):
  File "/home/user/legacy_kv/bin/run_server.py", line 87, in <module>
    db.load(os.environ.get('DB_DATA_PATH'))
  File "/home/user/legacy_kv/bin/db_wrapper.py", line 42, in load
    raise DatabaseCorruptionError("Header magic mismatch in data.bin")
DatabaseCorruptionError: Header magic mismatch in data.bin. 
Hint: Attempting to auto-recover...
Error: WAL_PATH environment variable not set. Cannot replay journal.
EOF

# 3. Create the WAL file
cat << 'EOF' > /home/user/legacy_kv/data/server-wal.log
BEGIN
SET SYSTEM_INIT true
SET ADMIN_PASSWORD initial_default_pass
COMMIT
BEGIN
SET TEMP_KEY 123
DELETE TEMP_KEY
COMMIT
BEGIN
SET ADMIN_PASSWORD intermediate_pass_441
ROLLBACK
BEGIN
SET USER_COUNT 5
SET ADMIN_PASSWORD secure_pass_8821_alpha
COMMIT
BEGIN
SET ADMIN_PASSWORD compromised_pass_999
SET USER_COUNT 6
# Crash happened here, no COMMIT
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
