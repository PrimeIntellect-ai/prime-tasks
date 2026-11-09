#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl jq postgresql postgresql-client sudo
pip3 install pytest flask pandas

mkdir -p /app

cat << 'EOF' > /app/api.py
from flask import Flask, request, jsonify

app = Flask(__name__)

data = [
    {"id": 1, "manager_id": None, "salary": 100},
    {"id": 2, "manager_id": 1, "salary": 50},
    {"id": 3, "manager_id": 1, "salary": 60},
    {"id": 4, "manager_id": 2, "salary": 40}
]

@app.route('/api/employees')
def employees():
    page = int(request.args.get('page', 1))
    if page == 1:
        return jsonify({"data": data[:2], "next_page": 2})
    elif page == 2:
        return jsonify({"data": data[2:], "next_page": None})
    return jsonify({"data": [], "next_page": None})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat << 'EOF' > /app/ground_truth.csv
1,250
2,90
3,60
4,40
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
su - postgres -c "/usr/lib/postgresql/14/bin/postgres -D /var/lib/postgresql/14/main -c config_file=/etc/postgresql/14/main/postgresql.conf" &
sleep 5
su - postgres -c "psql -c 'CREATE DATABASE org_db;'"
nohup python3 /app/api.py > /var/log/api.log 2>&1 &
sleep 2
EOF
chmod +x /app/start_services.sh

cat << 'EOF' > /app/verify_metric.py
import sys
import pandas as pd

try:
    pred = pd.read_csv('/home/user/total_salaries.csv', header=None, names=['id', 'total_salary'])
    truth = pd.read_csv('/app/ground_truth.csv', header=None, names=['id', 'total_salary'])

    if len(pred) != len(truth):
        print(0.0)
        sys.exit(0)

    pred = pred.sort_values('id').reset_index(drop=True)
    truth = truth.sort_values('id').reset_index(drop=True)

    matches = (pred['total_salary'] == truth['total_salary']).sum()
    accuracy = matches / len(truth)
    print(f"{accuracy:.4f}")
except Exception as e:
    print(0.0)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
