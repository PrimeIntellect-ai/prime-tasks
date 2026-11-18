#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/departments.csv
dept_id,parent_dept_id,dept_name
10,,Engineering
11,10,Frontend
12,10,Backend
13,12,Database
20,,Sales
21,20,NA Sales
22,20,EU Sales
30,,HR
31,30,Recruiting
EOF

    cat << 'EOF' > /home/user/data/projects.csv
project_id,dept_id,project_name
101,11,Web Portal
102,13,DB Migration
201,21,Q1 Campaign
202,22,EU Expansion
301,31,Hiring Drive
EOF

    cat << 'EOF' > /home/user/data/employees.csv
emp_id,hourly_rate,name
1,150,Alice
2,100,Bob
3,80,Charlie
4,120,Diana
5,90,Eve
EOF

    cat << 'EOF' > /home/user/data/timesheets.csv
emp_id,project_id,hours
1,101,10
2,102,20
3,201,15
4,202,5
1,202,5
5,301,10
3,301,8
EOF

    chmod -R 777 /home/user
