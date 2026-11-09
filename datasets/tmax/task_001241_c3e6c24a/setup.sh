#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git sqlite3 socat netcat-openbsd
pip3 install pytest

# Setup user and directories
useradd -m -s /bin/bash user || true
mkdir -p /home/user/app/repo
mkdir -p /home/user/corrupted_env

# Setup Git Repo
cd /home/user/app/repo
git init
git config user.name "Dev"
git config user.email "dev@example.com"

cat << 'EOF' > api_server.sh
#!/bin/bash
socat TCP4-LISTEN:8080,fork,reuseaddr EXEC:"cat >> /home/user/app/spool.log"
EOF
chmod +x api_server.sh

cat << 'EOF' > start_services.sh
#!/bin/bash
mkdir -p /home/user/app
sqlite3 /home/user/app/data.db "CREATE TABLE IF NOT EXISTS telemetry (id INTEGER PRIMARY KEY, sensor TEXT, value REAL);"
nohup ./api_server.sh > api.log 2>&1 &
nohup ./worker.sh > worker.log 2>&1 &
EOF
chmod +x start_services.sh

cat << 'EOF' > worker.sh
#!/bin/bash
mkdir -p /home/user/app
touch /home/user/app/spool.log
tail -F /home/user/app/spool.log | while read line; do
  sensor=$(echo "$line" | cut -d',' -f1)
  value=$(echo "$line" | cut -d',' -f2)
  if [ -n "$sensor" ] && [ -n "$value" ]; then
    sqlite3 /home/user/app/data.db "INSERT INTO telemetry (sensor, value) VALUES ('$sensor', $value);"
  fi
done
EOF
chmod +x worker.sh

git add .
git commit -m "Initial commit"

for i in $(seq 1 144); do
  echo "# commit $i" >> README.md
  git add README.md
  git commit -m "Commit $i"
done

cat << 'EOF' > worker.sh
#!/bin/bash
mkdir -p /home/user/app
touch /home/user/app/spool.log
tail -F /home/user/app/spool.log | while read line; do
  sensor=$(echo "$line" | cut -d',' -f1)
  value=$(echo "$line" | cut -d',' -f2)
  if [ -n "$sensor" ] && [ -n "$value" ]; then
    val=${value%.*}
    while [ "$val" -lt 0 ] 2>/dev/null; do
      sleep 0.1
    done
    sqlite3 /home/user/app/data.db "INSERT INTO telemetry (sensor, value) VALUES ('$sensor', $value);"
  fi
done
EOF
git add worker.sh
git commit -m "Update worker logic"

for i in $(seq 146 200); do
  echo "# commit $i" >> README.md
  git add README.md
  git commit -m "Commit $i"
done

# Setup corrupted env
cd /home/user/corrupted_env
python3 -c "
import sqlite3
import shutil

conn = sqlite3.connect('temp.db')
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('CREATE TABLE telemetry (id INTEGER PRIMARY KEY, sensor TEXT, value REAL)')
for i in range(5000):
    conn.execute(f\"INSERT INTO telemetry (sensor, value) VALUES ('sensorX', {float(i)})\")
conn.commit()

shutil.copy2('temp.db-wal', 'data.db-wal')
"
touch data.db
rm -f temp.db*

chmod -R 777 /home/user
