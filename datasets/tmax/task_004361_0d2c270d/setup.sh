#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 procps
pip3 install pytest pytz

useradd -m -s /bin/bash user || true

cd /home/user

# Setup SQLite database
cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('events.db')
cursor = conn.cursor()
cursor.execute('''CREATE TABLE logs (id INTEGER PRIMARY KEY, event_time TEXT, status TEXT)''')

# Insert data
events = [
    (1, '2024-05-01T01:00:00Z', 'FAIL'),     # April 30 21:00 EDT (Not May 1)
    (2, '2024-05-01T10:00:00Z', 'SUCCESS'),  # May 1 06:00 EDT (May 1)
    (3, '2024-05-02T02:00:00Z', 'SUCCESS'),  # May 1 22:00 EDT (May 1)
    (4, '2024-05-02T05:00:00Z', 'FAIL'),     # May 2 01:00 EDT (Not May 1)
]

cursor.executemany("INSERT INTO logs VALUES (?, ?, ?)", events)
conn.commit()
conn.close()
EOF
python3 setup_db.py
rm setup_db.py

# Create a script to start the background process when the container runs
# (Starting it in %post would cause the build to hang indefinitely)
cat << 'EOF' > /home/user/start_bg.sh
#!/bin/bash
if [ ! -f /home/user/.report_started ]; then
    touch /home/user/.report_started
    cat << 'INNEREOF' > /home/user/report.py
import sqlite3
import time

def generate_report():
    conn = sqlite3.connect('/home/user/events.db')
    cursor = conn.cursor()
    cursor.execute("SELECT id FROM logs WHERE event_time LIKE '2024-05-01%'")
    results = cursor.fetchall()
    print("Report results:", results)
    conn.close()

if __name__ == "__main__":
    generate_report()
    time.sleep(999999)
INNEREOF
    cd /home/user
    python3 report.py >/dev/null 2>&1 &
    sleep 0.5
    rm -f /home/user/report.py
fi
EOF
chmod +x /home/user/start_bg.sh

# Inject into bashrc for interactive shells
echo "source /home/user/start_bg.sh" >> /home/user/.bashrc
echo "source /home/user/start_bg.sh" >> /etc/bash.bashrc

# Inject into python's sitecustomize to ensure it runs even if the test runs python directly
cat << 'EOF' > /usr/lib/python3.10/sitecustomize.py
import os
if not os.path.exists('/home/user/.report_started'):
    try:
        open('/home/user/.report_started', 'w').close()
        os.system('bash /home/user/start_bg.sh')
    except:
        pass
EOF

chmod -R 777 /home/user
