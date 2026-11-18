#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask rdflib

    mkdir -p /app/backup_graph_server

    cat << 'EOF' > /app/backup_graph_server/app.py
from flask import Flask, request, jsonify
import rdflib
from queries import get_failed_backups_query

app = Flask(__name__)
g = rdflib.Graph()
g.parse("/home/user/backups.ttl", format="turtle")

@app.route('/api/failed_backups', methods=['GET'])
def failed_backups():
    date = request.args.get('date')
    q = get_failed_backups_query(date)
    results = g.query(q)
    output = []
    for row in results:
        output.append({
            "serverName": str(row.serverName),
            "jobId": str(row.jobId)
        })
    return jsonify(output)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9000)
EOF

    cat << 'EOF' > /app/backup_graph_server/queries.py
def get_failed_backups_query(date: str) -> str:
    # Deliberate implicit cross join bug (missing the link between server and job)
    return f"""
    PREFIX ex: <http://backup.local/vocab#>
    SELECT ?serverName ?jobId
    WHERE {{
        ?job a ex:BackupJob ;
             ex:date "{date}" ;
             ex:status "FAILED" ;
             ex:jobId ?jobId .
        ?server a ex:Server ;
                ex:name ?serverName .
    }}
    """
EOF

    cat << 'EOF' > /app/backup_graph_server/start.sh
#!/bin/bash
export FLASK_APP=app.py
# PERTURBATION: typo in flask command and missing host binding
flosk run --port 9000
EOF
    chmod +x /app/backup_graph_server/start.sh

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backups.ttl
@prefix ex: <http://backup.local/vocab#> .

<http://backup.local/server/1> a ex:Server ;
    ex:name "db-01" ;
    ex:hasJob <http://backup.local/job/101>, <http://backup.local/job/102> .

<http://backup.local/server/2> a ex:Server ;
    ex:name "app-01" ;
    ex:hasJob <http://backup.local/job/201> .

<http://backup.local/job/101> a ex:BackupJob ;
    ex:jobId "job-101" ;
    ex:date "2023-10-15" ;
    ex:status "SUCCESS" .

<http://backup.local/job/102> a ex:BackupJob ;
    ex:jobId "job-102" ;
    ex:date "2023-10-15" ;
    ex:status "FAILED" .

<http://backup.local/job/201> a ex:BackupJob ;
    ex:jobId "job-201" ;
    ex:date "2023-10-15" ;
    ex:status "SUCCESS" .
EOF

    chmod -R 777 /home/user
