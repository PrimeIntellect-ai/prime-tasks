#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow flask

    mkdir -p /app

    # Create the initial etl.py with a bad query
    cat << 'EOF' > /app/etl.py
import sqlite3

def run_etl():
    conn = sqlite3.connect('/app/data.db')
    cursor = conn.cursor()
    # Bad query with implicit cross join
    query = """
    SELECT e.id, e.name, e.salary, d.id
    FROM employees e, departments d, employee_departments ed
    """
    cursor.execute(query)
    results = cursor.fetchall()
    print(f"Fetched {len(results)} rows.")
    conn.close()

if __name__ == '__main__':
    run_etl()
EOF

    # Create the database and populate it
    python3 -c "
import sqlite3

conn = sqlite3.connect('/app/data.db')
c = conn.cursor()

c.execute('''CREATE TABLE employees (id INTEGER, name TEXT, salary INTEGER)''')
c.execute('''CREATE TABLE departments (id TEXT)''')
c.execute('''CREATE TABLE employee_departments (employee_id INTEGER, department_id TEXT)''')

employees = [
    (1, 'Alice', 100000),
    (2, 'Bob', 120000),
    (3, 'Charlie', 90000),
    (4, 'Diana', 110000)
]
departments = [('D1',), ('D2',), ('D3',)]
employee_departments = [
    (1, 'D2'),
    (2, 'D2'),
    (3, 'D3'),
    (4, 'D1')
]

c.executemany('INSERT INTO employees VALUES (?, ?, ?)', employees)
c.executemany('INSERT INTO departments VALUES (?)', departments)
c.executemany('INSERT INTO employee_departments VALUES (?, ?)', employee_departments)

conn.commit()
conn.close()
"

    # Create the events.json file
    cat << 'EOF' > /app/events.json
{"employee_id": 1, "event_type": "login"}
{"employee_id": 1, "event_type": "login"}
{"employee_id": 2, "event_type": "logout"}
{"employee_id": 3, "event_type": "login"}
EOF

    # Create the schema_clue.png image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'MAPPING: {\"D1\": \"Operations\", \"D2\": \"Engineering\", \"D3\": \"Sales\"}', fill=(0,0,0))
img.save('/app/schema_clue.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
