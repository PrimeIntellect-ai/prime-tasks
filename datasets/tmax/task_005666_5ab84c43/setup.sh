#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    sqlite3 graph.db <<EOF
CREATE TABLE edges (source_id INTEGER, target_id INTEGER);

-- Insert relationships (bidirectional)
-- Cluster 1: 1 and 6 share 4 friends (2,3,4,5)
INSERT INTO edges VALUES (1,2), (2,1), (1,3), (3,1), (1,4), (4,1), (1,5), (5,1);
INSERT INTO edges VALUES (6,2), (2,6), (6,3), (3,6), (6,4), (4,6), (6,5), (5,6);

-- Cluster 2: 1 and 7 share 3 friends (2,3,4)
INSERT INTO edges VALUES (7,2), (2,7), (7,3), (3,7), (7,4), (4,7);

-- Cluster 3: 8 and 9 share 2 friends (10, 11)
INSERT INTO edges VALUES (8,10), (10,8), (8,11), (11,8);
INSERT INTO edges VALUES (9,10), (10,9), (9,11), (11,9);

-- Cluster 4: 12 and 13 share 1 friend (14)
INSERT INTO edges VALUES (12,14), (14,12), (13,14), (14,13);

-- Create some noise
INSERT INTO edges VALUES (15,16), (16,15), (17,18), (18,17);
EOF

    cat << 'EOF' > analyze.go
package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

type Recommendation struct {
	User1         int `json:"user1"`
	User2         int `json:"user2"`
	MutualFriends int `json:"mutual_friends"`
	Rank          int `json:"rank"`
}

func main() {
	db, err := sql.Open("sqlite3", "./graph.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// BUGGY QUERY: Implicit cross join, wrong filtering, no window functions
	query := `
		SELECT e1.source_id as user1, e2.target_id as user2, COUNT(*) as mutual_friends, 1 as rank
		FROM edges e1, edges e2
		WHERE e1.source_id != e2.target_id
		GROUP BY user1, user2
		LIMIT 10
	`

	rows, err := db.Query(query)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	var recs []Recommendation
	for rows.Next() {
		var r Recommendation
		if err := rows.Scan(&r.User1, &r.User2, &r.MutualFriends, &r.Rank); err != nil {
			log.Fatal(err)
		}
		recs = append(recs, r)
	}

	file, err := os.Create("recommendations.json")
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(recs); err != nil {
		log.Fatal(err)
	}
}
EOF

    chmod -R 777 /home/user
