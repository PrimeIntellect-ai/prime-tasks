#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
ID,Name,Department,Salary
1,Alice ,Engineering,80000
2, Bob,Engineering,
3,Charlie,Sales,50000
4,Diana ,Sales,
5, Eve,HR,60000
EOF

    cat << 'EOF' > /home/user/projects.json
[
  {"Employee_ID": 1, "Project_Name": "Alpha", "Start_Date": "01/15/2023"},
  {"Employee_ID": 2, "Project_Name": "Beta", "Start_Date": "2023-02-20"},
  {"Employee_ID": 3, "Project_Name": "Gamma", "Start_Date": "March 5, 2023"},
  {"Employee_ID": 4, "Project_Name": "Delta", "Start_Date": "invalid_date"},
  {"Employee_ID": 5, "Project_Name": "Epsilon", "Start_Date": "04/10/2023"}
]
EOF

    chmod -R 777 /home/user
