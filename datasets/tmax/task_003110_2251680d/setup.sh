#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq sqlite3 gawk coreutils
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/employees.csv
emp_id,name,department_id
1,Alice,10
2,Bob,10
3,Charlie,20
4,Diana,10
5,Eve,20
6,Frank,30
7,Grace,10
8,Heidi,20
9,Ivan,30
10,Judy,30
EOF

cat << 'EOF' > /home/user/mentorships.csv
mentor_id,mentee_id
1,2
2,4
1,3
3,5
5,3
6,9
9,10
7,1
8,5
10,6
9,1
EOF

cat << 'EOF' > /home/user/expected_same_dept_mentorships.json
{
  "10": [
    [
      "Alice",
      "Bob"
    ],
    [
      "Bob",
      "Diana"
    ],
    [
      "Grace",
      "Alice"
    ]
  ],
  "20": [
    [
      "Charlie",
      "Eve"
    ],
    [
      "Eve",
      "Charlie"
    ],
    [
      "Heidi",
      "Eve"
    ]
  ],
  "30": [
    [
      "Frank",
      "Ivan"
    ],
    [
      "Ivan",
      "Judy"
    ],
    [
      "Judy",
      "Frank"
    ]
  ]
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
