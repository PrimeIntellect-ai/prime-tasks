#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true

    # Create schema.json
    cat << 'EOF' > /home/user/schema.json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "employee_name": {"type": "string"},
      "department_name": {"type": "string"},
      "project_name": {"type": "string"},
      "manager_name": {"type": "string"},
      "manager_department": {"type": "string"}
    },
    "required": ["employee_name", "department_name", "project_name", "manager_name", "manager_department"]
  }
}
EOF

    # Create graph.db and populate it
    sqlite3 /home/user/graph.db << 'EOF'
CREATE TABLE Entity (id INTEGER PRIMARY KEY, name TEXT, label TEXT);
CREATE TABLE Relation (source_id INTEGER, target_id INTEGER, rel_type TEXT);

-- Data
INSERT INTO Entity VALUES (1, 'Alice', 'Person');
INSERT INTO Entity VALUES (2, 'Bob', 'Person');
INSERT INTO Entity VALUES (3, 'Charlie', 'Person');
INSERT INTO Entity VALUES (4, 'Engineering', 'Department');
INSERT INTO Entity VALUES (5, 'Sales', 'Department');
INSERT INTO Entity VALUES (6, 'Project X', 'Project');
INSERT INTO Entity VALUES (7, 'Project Y', 'Project');
INSERT INTO Entity VALUES (8, 'Dave', 'Person');
INSERT INTO Entity VALUES (9, 'Marketing', 'Department');

-- Alice works for Engineering, which manages Project X. Alice is assigned to Project X.
INSERT INTO Relation VALUES (1, 4, 'WORKS_FOR');
INSERT INTO Relation VALUES (4, 6, 'MANAGES');
INSERT INTO Relation VALUES (1, 6, 'ASSIGNED_TO');

-- Alice reports to Bob. Bob works for Sales. (Matches criteria)
INSERT INTO Relation VALUES (1, 2, 'REPORTS_TO');
INSERT INTO Relation VALUES (2, 5, 'WORKS_FOR');

-- Charlie works for Sales, which manages Project Y. Charlie is assigned to Project Y.
INSERT INTO Relation VALUES (3, 5, 'WORKS_FOR');
INSERT INTO Relation VALUES (5, 7, 'MANAGES');
INSERT INTO Relation VALUES (3, 7, 'ASSIGNED_TO');

-- Charlie reports to Dave. Dave works for Sales. (Fails criteria: Manager in same Dept)
INSERT INTO Relation VALUES (3, 8, 'REPORTS_TO');
INSERT INTO Relation VALUES (8, 5, 'WORKS_FOR');
EOF

    chmod -R 777 /home/user
