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
