#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ticket_4092/libs
    mkdir -p /tmp/wrong_path

    cat << 'EOF' > /tmp/wrong_path/calc.py
def moving_average(data, window_size=3):
    print("WARNING: Using dummy math module!")
    return []
EOF

    cat << 'EOF' > /home/user/ticket_4092/libs/calc.py
def moving_average(data, window_size=3):
    if len(data) < window_size:
        return []
    # BUG: Off-by-one error. range(len(data) - window_size) misses the final window.
    # FIX: range(len(data) - window_size + 1)
    return [sum(data[i:i+window_size])/window_size for i in range(len(data) - window_size)]
EOF

    cat << 'EOF' > /home/user/ticket_4092/analyze.py
import os
import sys
import sqlite3

# Import library based on environment variable
lib_path = os.environ.get("CALC_LIB_PATH", "/tmp/wrong_path")
sys.path.insert(0, lib_path)
import calc

def main():
    db_path = "/home/user/ticket_4092/records.db"
    input_list = "/home/user/ticket_4092/input_files.txt"
    output_file = "/home/user/ticket_4092/result.txt"

    values = []

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    with open(input_list, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            # BUG: .split()[0] truncates filenames with spaces
            # FIX: filename = line.strip()
            filename = line.split()[0]

            cursor.execute("SELECT value FROM measurements WHERE filename = ?", (filename,))
            row = cursor.fetchone()
            if row:
                values.append(row[0])
            else:
                print(f"Missing data for {filename}")

    conn.close()

    m_avg = calc.moving_average(values, 3)

    with open(output_file, 'w') as f:
        f.write(",".join(f"{x:.2f}" for x in m_avg))
        f.write("\n")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/ticket_4092/run.sh
#!/bin/bash
# BUG: Points to the wrong directory
# FIX: export CALC_LIB_PATH="/home/user/ticket_4092/libs"
export CALC_LIB_PATH="/tmp/wrong_path"

python3 /home/user/ticket_4092/analyze.py
EOF

    chmod +x /home/user/ticket_4092/run.sh

    cat << 'EOF' > /home/user/ticket_4092/input_files.txt
data_01.csv
data 02.csv
data_03.csv
data 04.csv
data_05.csv
EOF

    python3 -c '
import sqlite3
conn = sqlite3.connect("/home/user/ticket_4092/records.db")
c = conn.cursor()
c.execute("CREATE TABLE measurements (id INTEGER PRIMARY KEY, filename TEXT, value REAL)")
data = [
    ("data_01.csv", 10.0),
    ("data 02.csv", 20.0),
    ("data_03.csv", 30.0),
    ("data 04.csv", 40.0),
    ("data_05.csv", 50.0)
]
c.executemany("INSERT INTO measurements (filename, value) VALUES (?, ?)", data)
conn.commit()
conn.close()
'

    chmod -R 777 /home/user
