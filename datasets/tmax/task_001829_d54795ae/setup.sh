#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/employees.csv
emp_id,emp_name,manager_id,cost
1,Alice,,100
2,Bob,1,200
3,Charlie,1,150
4,David,2,50
5,Eve,2,300
6,Frank,3,100
7,Grace,,500
8,Heidi,7,200
EOF

cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "$ref": "#/definitions/employee"
  },
  "definitions": {
    "employee": {
      "type": "object",
      "properties": {
        "emp_id": { "type": "integer" },
        "emp_name": { "type": "string" },
        "cost": { "type": "integer" },
        "total_team_cost": { "type": "integer" },
        "subordinates": {
          "type": "array",
          "items": { "$ref": "#/definitions/employee" }
        }
      },
      "required": ["emp_id", "emp_name", "cost", "total_team_cost", "subordinates"],
      "additionalProperties": false
    }
  }
}
EOF

chmod -R 777 /home/user
