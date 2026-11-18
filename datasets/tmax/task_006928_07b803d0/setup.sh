#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest rdflib jsonschema

    mkdir -p /home/user
    cd /home/user

    # Create SQLite Database
    cat << 'EOF' > setup.sql
CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, dept_id INTEGER);
CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT, lead_id INTEGER);

INSERT INTO departments VALUES (1, 'Engineering'), (2, 'HR'), (3, 'Sales');
INSERT INTO employees VALUES (101, 'Alice', NULL, 1);
INSERT INTO employees VALUES (102, 'Bob', 101, 1);
INSERT INTO employees VALUES (103, 'Charlie', 101, 1);
INSERT INTO employees VALUES (104, 'Diana', NULL, 2);
INSERT INTO employees VALUES (105, 'Eve', 104, 2);
INSERT INTO projects VALUES (1001, 'Apollo', 101);
INSERT INTO projects VALUES (1002, 'Hermes', 104);
INSERT INTO projects VALUES (1003, 'Zeus', 102); -- Bob has 0 direct reports
EOF
    sqlite3 company.db < setup.sql
    rm setup.sql

    # Create RDF File
    cat << 'EOF' > knowledge.ttl
@prefix ex: <http://example.org/> .

ex:proj1 ex:projectName "Apollo" ;
         ex:riskLevel "High" .

ex:proj2 ex:projectName "Hermes" ;
         ex:riskLevel "Low" .

ex:proj3 ex:projectName "Zeus" ;
         ex:riskLevel "Medium" .
EOF

    # Create JSON Schema
    cat << 'EOF' > schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "project_name": { "type": "string" },
    "lead_name": { "type": "string" },
    "department_name": { "type": "string" },
    "direct_reports": { "type": "integer", "minimum": 1 },
    "risk_level": { "type": "string" }
  },
  "required": ["project_name", "lead_name", "department_name", "direct_reports", "risk_level"]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
