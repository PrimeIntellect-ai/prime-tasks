#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go sqlite3 curl
    pip3 install pytest flask pandas

    mkdir -p /app /home/user/data /home/user/etl

    # Create the data sink Flask app
    cat << 'EOF' > /app/sink.py
from flask import Flask, request
import sqlite3
import os

app = Flask(__name__)

def init_db():
    conn = sqlite3.connect('/app/sink.db')
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS records
                 (id TEXT, notes TEXT, email TEXT, email_domain TEXT, event_date TEXT)''')
    conn.commit()
    conn.close()

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    if not data:
        return "Bad Request", 400
    conn = sqlite3.connect('/app/sink.db')
    c = conn.cursor()
    c.execute("INSERT INTO records VALUES (?, ?, ?, ?, ?)",
              (data.get('id', ''), data.get('notes', ''), data.get('email', ''), data.get('email_domain', ''), data.get('event_date', '')))
    conn.commit()
    conn.close()
    return "OK", 200

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
EOF

    # Initialize the database
    python3 -c "import sqlite3; conn = sqlite3.connect('/app/sink.db'); c = conn.cursor(); c.execute('''CREATE TABLE IF NOT EXISTS records (id TEXT, notes TEXT, email TEXT, email_domain TEXT, event_date TEXT)'''); conn.commit(); conn.close()"

    # Create the input CSV with embedded newlines and messy data
    cat << 'EOF' > /home/user/data/input.csv
id,notes,contact_info,event_date
101,"hello
world",Reach out to john.doe@example.com for info,12/31/2022
102,"no newlines here",Contact us at support@test.com,2022-12-31
103,"carriage
return",No email here,31-12-2022
EOF

    # Create the golden output CSV for verification
    cat << 'EOF' > /app/golden_output.csv
id,notes,email,email_domain,event_date
101,hello world,john.doe@example.com,example.com,2022-12-31
102,no newlines here,support@test.com,test.com,2022-12-31
103,carriage return,,,2022-12-31
EOF

    # Create the buggy Go ETL worker
    cat << 'EOF' > /home/user/etl/main.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	file, err := os.Open("/home/user/data/input.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		fmt.Println("Processing:", line)
		// Buggy implementation: splits on comma, naive date parsing, no regex, fails on newlines
		parts := strings.Split(line, ",")
		if len(parts) >= 4 {
			// push to sink...
		}
	}
}
EOF

    # Create the verifier script
    cat << 'EOF' > /home/user/verifier.py
import sqlite3
import pandas as pd

def calculate_accuracy():
    conn = sqlite3.connect('/app/sink.db')
    df_agent = pd.read_sql_query("SELECT id, notes, email, email_domain, event_date FROM records", conn)
    conn.close()

    df_golden = pd.read_csv('/app/golden_output.csv')
    df_golden = df_golden.fillna('')
    df_agent = df_agent.fillna('')

    merged = pd.merge(df_golden, df_agent, on='id', suffixes=('_gold', '_agent'))

    correct = 0
    for _, row in merged.iterrows():
        if (row['notes_gold'] == row['notes_agent'] and
            row['email_gold'] == row['email_agent'] and
            row['email_domain_gold'] == row['email_domain_agent'] and
            row['event_date_gold'] == row['event_date_agent']):
            correct += 1

    total_expected = len(df_golden)
    accuracy = correct / total_expected if total_expected > 0 else 0
    print(f"Accuracy: {accuracy}")

    if accuracy >= 0.95:
        exit(0)
    else:
        exit(1)

if __name__ == '__main__':
    calculate_accuracy()
EOF

    # Create a startup script for the service
    cat << 'EOF' > /start.sh
#!/bin/bash
nohup python3 /app/sink.py > /app/sink.log 2>&1 &
EOF
    chmod +x /start.sh

    # Create user and ensure service starts on login if needed
    useradd -m -s /bin/bash user || true
    echo "nohup python3 /app/sink.py > /app/sink.log 2>&1 &" >> /home/user/.bashrc

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
