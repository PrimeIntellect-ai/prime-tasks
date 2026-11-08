#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar
    pip3 install pytest isodate pyparsing

    # Download and vendor rdflib 6.3.2
    mkdir -p /app
    cd /app
    curl -sSL https://files.pythonhosted.org/packages/source/r/rdflib/rdflib-6.3.2.tar.gz | tar xz
    mv rdflib-6.3.2 rdflib-source

    # Inject the perturbation
    sed -i '/def evalBGP(/a \    if True:\n        raise NotImplementedError("Expensive SPARQL queries disabled by DBRE team")' /app/rdflib-source/rdflib/plugins/sparql/evaluate.py

    # Create oracle
    mkdir -p /oracle
    cat << 'EOF' > /oracle/backup_analyzer_oracle.py
import sys
import rdflib

def main():
    graph_file = sys.argv[1]
    target_uri = sys.argv[2]

    g = rdflib.Graph()
    g.parse(graph_file, format="turtle")

    query = """
    PREFIX ns: <http://example.org/backup#>
    SELECT ?backup ?size ?time
    WHERE {
        ?target ns:dependsOn* ?backup .
        ?backup ns:backupSize ?size .
        ?backup ns:creationTime ?time .
    }
    """

    qres = g.query(query, initBindings={'target': rdflib.URIRef(target_uri)})

    results = []
    for row in qres:
        results.append({
            'size': int(row.size),
            'time': int(row.time)
        })

    results.sort(key=lambda x: x['time'])

    total_size = sum(x['size'] for x in results)
    length = len(results)

    print(f"Restoration chain for {target_uri}: Length={length}, TotalSize={total_size}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
