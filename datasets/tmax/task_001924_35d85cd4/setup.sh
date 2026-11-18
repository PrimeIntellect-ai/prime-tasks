#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/employees.jsonl
{"id": "e01", "name": "Alice", "department": "Engineering", "salary": 120000, "status": "active", "join_date": "2020-01-15"}
{"id": "e02", "name": "Bob", "department": "Sales", "salary": 85000, "status": "active", "join_date": "2021-03-10"}
{"id": "e03", "name": "Charlie", "department": "Engineering", "salary": 95000, "status": "inactive", "join_date": "2019-11-20"}
{"id": "e04", "name": "Diana", "department": "Engineering", "salary": 130000, "status": "active", "join_date": "2022-05-01"}
{"id": "e05", "name": "Evan", "department": "Marketing", "salary": 75000, "status": "active", "join_date": "2020-08-12"}
{"id": "e06", "name": "Fiona", "department": "Engineering", "salary": 115000, "status": "active", "join_date": "2021-09-30"}
{"id": "e07", "name": "George", "department": "Sales", "salary": 90000, "status": "inactive", "join_date": "2018-02-14"}
{"id": "e08", "name": "Hannah", "department": "Engineering", "salary": 140000, "status": "active", "join_date": "2017-06-25"}
{"id": "e09", "name": "Ian", "department": "HR", "salary": 65000, "status": "active", "join_date": "2023-01-10"}
{"id": "e10", "name": "Julia", "department": "Engineering", "salary": 105000, "status": "active", "join_date": "2022-11-05"}
EOF

    chmod -R 777 /home/user
