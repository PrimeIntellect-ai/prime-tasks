#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang sqlite3
pip3 install pytest

mkdir -p /home/user
cd /home/user

# Create SQLite database
sqlite3 /home/user/backup_graph.db <<EOF
CREATE TABLE Nodes (
    id INTEGER PRIMARY KEY,
    label TEXT,
    props TEXT
);

CREATE TABLE Edges (
    source INTEGER,
    target INTEGER,
    rel_type TEXT,
    FOREIGN KEY(source) REFERENCES Nodes(id),
    FOREIGN KEY(target) REFERENCES Nodes(id)
);

-- Insert Nodes
INSERT INTO Nodes (id, label, props) VALUES (1, 'Service', '{"name": "PaymentService", "owner": "fin"}');
INSERT INTO Nodes (id, label, props) VALUES (2, 'Service', '{"name": "AuthService", "owner": "sec"}');
INSERT INTO Nodes (id, label, props) VALUES (3, 'Database', '{"name": "TxDB", "type": "postgres"}');
INSERT INTO Nodes (id, label, props) VALUES (4, 'Database', '{"name": "LedgerDB", "type": "mysql"}');
INSERT INTO Nodes (id, label, props) VALUES (5, 'Database', '{"name": "UserDB", "type": "mongo"}');
INSERT INTO Nodes (id, label, props) VALUES (6, 'Storage', '{"name": "FastBlock", "size": "10TB"}');
INSERT INTO Nodes (id, label, props) VALUES (7, 'Storage', '{"name": "ColdArchive", "size": "50TB"}');

-- Insert Edges
INSERT INTO Edges (source, target, rel_type) VALUES (1, 3, 'USES_DB');
INSERT INTO Edges (source, target, rel_type) VALUES (1, 4, 'USES_DB');
INSERT INTO Edges (source, target, rel_type) VALUES (2, 5, 'USES_DB');
INSERT INTO Edges (source, target, rel_type) VALUES (3, 6, 'STORED_ON');
INSERT INTO Edges (source, target, rel_type) VALUES (4, 7, 'STORED_ON');
INSERT INTO Edges (source, target, rel_type) VALUES (5, 6, 'STORED_ON');
EOF

# Create buggy Go script
cat << 'EOF' > /home/user/extract_chain.go
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

type Chain struct {
	ServiceName  string `json:"service_name"`
	DatabaseName string `json:"database_name"`
	StorageName  string `json:"storage_name"`
}

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Please provide a service name")
	}
	serviceName := os.Args[1]

	db, err := sql.Open("sqlite3", "/home/user/backup_graph.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// BUGGY QUERY: Cartesian product / implicit cross join, plus SQL injection vulnerability (not parameterized)
	query := fmt.Sprintf(`
		SELECT n1.props, n2.props, n3.props
		FROM Nodes n1, Nodes n2, Nodes n3, Edges e1, Edges e2
		WHERE n1.label = 'Service' 
		  AND json_extract(n1.props, '$.name') = '%s'
		  AND n2.label = 'Database' 
		  AND n3.label = 'Storage'
	`, serviceName)

	rows, err := db.Query(query)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	var results []Chain
	for rows.Next() {
		var p1, p2, p3 string
		if err := rows.Scan(&p1, &p2, &p3); err != nil {
			log.Fatal(err)
		}

		var m1, m2, m3 map[string]interface{}
		json.Unmarshal([]byte(p1), &m1)
		json.Unmarshal([]byte(p2), &m2)
		json.Unmarshal([]byte(p3), &m3)

		results = append(results, Chain{
			ServiceName:  m1["name"].(string),
			DatabaseName: m2["name"].(string),
			StorageName:  m3["name"].(string),
		})
	}

	out, _ := json.MarshalIndent(results, "", "  ")
	err = os.WriteFile("/home/user/dependency_chains.json", out, 0644)
	if err != nil {
		log.Fatal(err)
	}
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
