#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

sqlite3 /home/user/compliance.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
INSERT INTO employees VALUES (1, 'Alice', 'Trading'), (2, 'Bob', 'Research'), (3, 'Charlie', 'Trading'), (4, 'Dave', 'Sales'), (5, 'Eve', 'Trading');

CREATE TABLE transfers (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount INTEGER, date TEXT);
INSERT INTO transfers VALUES 
(1, 1, 2, 100, '2023-01-01'), 
(2, 1, 3, 200, '2023-01-02'), 
(3, 1, 4, 50, '2023-01-03'), 
(4, 3, 2, 500, '2023-01-04'), 
(5, 3, 4, 100, '2023-01-05'), 
(6, 4, 1, 50, '2023-01-06'),
(7, 5, 2, 50, '2023-01-07'),
(8, 5, 3, 50, '2023-01-08'),
(9, 5, 4, 50, '2023-01-09'),
(10, 5, 1, 50, '2023-01-10');

CREATE TABLE messages (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, content TEXT, date TEXT);
INSERT INTO messages VALUES 
(1, 1, 2, 'urgent: buy', '2023-01-01'), 
(2, 1, 3, 'hello', '2023-01-02'), 
(3, 1, 4, 'urgent: sell', '2023-01-03'), 
(4, 3, 2, 'urgent: meeting', '2023-01-04'),
(5, 5, 1, 'just checking in', '2023-01-05');
EOF

cat << 'EOF' > /home/user/audit_report.sql
SELECT e.name, SUM(t.amount) as total_sent
FROM employees e, transfers t, messages m
WHERE e.id = t.sender_id
  AND e.id = m.sender_id
  AND m.content LIKE '%urgent%'
GROUP BY e.name;
EOF

chmod -R 777 /home/user
