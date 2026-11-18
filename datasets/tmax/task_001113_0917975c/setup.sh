#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/survey_data

    cat << 'EOF' > /home/user/metadata.csv
emp_id,hire_year,office_city
EMP00001,2015,New York
EMP00002,2018,London
EMP00003,2020,Tokyo
EMP00004,2012,Chicago
EMP00005,2021,Paris
EMP00006,2019,Sydney
EMP00007,2017,Berlin
EOF

    cat << 'EOF' > /home/user/survey_data/survey_NA.csv
emp_id,q1_satisfaction,q2_workload,q3_culture,q4_management
EMP00001,8,7,9,10
EMP00004,5,11,8,9
EMP00X01,7,7,7,7
EOF

    cat << 'EOF' > /home/user/survey_data/survey_EU.csv
emp_id,q1_satisfaction,q2_workload,q3_culture,q4_management
EMP00002,6,6,8,7
EMP00005,9,8,10,9
EMP00007,1,2,0,5
EOF

    cat << 'EOF' > /home/user/survey_data/survey_APAC.csv
emp_id,q1_satisfaction,q2_workload,q3_culture,q4_management
EMP00003,7,7,7,7
EMP00006,8,9,8,
EMP00008,5,5,5,5
EOF

    chmod -R 777 /home/user
