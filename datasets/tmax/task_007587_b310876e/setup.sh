#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/infrastructure.ttl
@prefix ex: <http://example.org/> .

ex:DB1 a ex:Database ;
    ex:name "users_db" ;
    ex:hostedOn ex:Host1 .

ex:DB2 a ex:Database ;
    ex:name "payments_db" ;
    ex:hostedOn ex:Host2 .

ex:DB3 a ex:Database ;
    ex:name "logs_db" ;
    ex:hostedOn ex:Host3 .

ex:Host1 a ex:Host ;
    ex:hasPolicy ex:PolicyA .

ex:Host2 a ex:Host ;
    ex:hasPolicy ex:PolicyB .

ex:Host3 a ex:Host ;
    ex:hasPolicy ex:PolicyC .

ex:PolicyA a ex:BackupPolicy ;
    ex:name "hourly_snapshot" .

ex:PolicyB a ex:BackupPolicy ;
    ex:name "daily_incremental" .

ex:PolicyC a ex:BackupPolicy ;
    ex:name "weekly_full" .
EOF

    cat << 'EOF' > /home/user/export_backup_metadata.py
import rdflib
import json

def generate_manifest():
    g = rdflib.Graph()
    g.parse("/home/user/infrastructure.ttl", format="turtle")

    # FLAWED QUERY: Note how ?host and ?someHost are disconnected, creating a cross join.
    query = """
    PREFIX ex: <http://example.org/>
    SELECT ?dbName ?policyName
    WHERE {
        ?db a ex:Database ;
            ex:name ?dbName ;
            ex:hostedOn ?host .

        ?someHost ex:hasPolicy ?policy .

        ?policy a ex:BackupPolicy ;
            ex:name ?policyName .
    }
    """

    results = g.query(query)

    manifest = []
    for row in results:
        manifest.append({
            "database": str(row.dbName),
            "policy": str(row.policyName)
        })

    # Sort to ensure consistent output
    manifest = sorted(manifest, key=lambda x: x["database"])

    with open("/home/user/backup_manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)

if __name__ == "__main__":
    generate_manifest()
EOF

    chmod -R 777 /home/user
