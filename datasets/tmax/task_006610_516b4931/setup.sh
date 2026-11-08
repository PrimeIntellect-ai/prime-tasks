#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_survey.csv
id,name,email,department,q1,q2,q3,feedback
1,Alice,ALICE@test.com,HR,5.0,4.0,,Great job!
2,Bob,bob@test.com,ENG,,3.0,2.0,"This feedback
has an embedded newline"
3,Charlie,charlie@test.com,HR,1.0,2.0,3.0,Okay
4,David,david@test.com,ENG,4.0,,5.0,Excellent
5,Eve,eve@test.com,ENG,5.0,5.0,4.0,Good
6,Frank,frank@test.com,HR,3.0,3.0,3.0,Fair
7,Grace,grace@test.com,ENG,2.0,1.0,,Needs work
8,Heidi,heidi@test.com,HR,4.0,5.0,5.0,Awesome
9,Ivan,ivan@test.com,ENG,1.0,,1.0,"Another
newline"
10,Judy,judy@test.com,ENG,5.0,4.0,4.0,Perfect
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
