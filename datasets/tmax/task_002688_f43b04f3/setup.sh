#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go sqlite3 gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    cd /home/user/app

    sqlite3 company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT, employee_id INTEGER);

INSERT INTO employees VALUES (1, 'Alice', NULL);
INSERT INTO employees VALUES (2, 'Bob', 1);
INSERT INTO employees VALUES (3, 'Charlie', 2);
INSERT INTO employees VALUES (4, 'Dave', 1);

INSERT INTO projects VALUES (101, 'Project Alpha', 2);
INSERT INTO projects VALUES (102, 'Project Beta', 3);
INSERT INTO projects VALUES (103, 'Project Gamma', 3);
EOF

    cat << 'EOF' > /home/user/app/main.go
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

type Result struct {
	EmployeeName string `json:"employee_name"`
	ProjectName  string `json:"project_name"`
}

func main() {
	db, err := sql.Open("sqlite3", "./company.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// BUGGY QUERY: implicit cross join
	query := `
	WITH RECURSIVE subordinates AS (
		SELECT id, name, manager_id FROM employees WHERE id = ?
		UNION ALL
		SELECT e.id, e.name, e.manager_id FROM employees e
		INNER JOIN subordinates s ON s.id = e.manager_id
	)
	SELECT s.name, p.name 
	FROM subordinates s, projects p;
	`

	rows, err := db.Query(query, 1)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	var results []Result
	for rows.Next() {
		var r Result
		var pName sql.NullString
		if err := rows.Scan(&r.EmployeeName, &pName); err != nil {
			log.Fatal(err)
		}
		if pName.Valid {
			r.ProjectName = pName.String
		}
		results = append(results, r)
	}

	// Dump to JSON...
}
EOF

    chmod -R 777 /home/user
