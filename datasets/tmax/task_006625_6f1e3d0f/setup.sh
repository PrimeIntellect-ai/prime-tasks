#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest jsonschema

    mkdir -p /home/user

    cat << 'EOF' > /home/user/tasks.csv
task_id,task_name
T1,Design
T2,Implementation
T3,Testing
T4,Deployment
T5,Code Review
EOF

    cat << 'EOF' > /home/user/dependencies.csv
dependent_task,prerequisite_task,weight
T2,T1,10
T3,T2,20
T5,T3,15
T2,T5,5
T4,T3,30
EOF

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "$ref": "#/definitions/task"
  },
  "definitions": {
    "task": {
      "type": "object",
      "properties": {
        "task_id": { "type": "string" },
        "task_name": { "type": "string" },
        "dependents": {
          "type": "array",
          "items": { "$ref": "#/definitions/task" }
        }
      },
      "required": ["task_id", "task_name", "dependents"]
    }
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
