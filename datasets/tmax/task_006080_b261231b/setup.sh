#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/users.csv
user_id,age,country
101,25,US
102,35,UK
103,40,CA
104,22,US
105,30,AU
106,45,IN
107,29,US
EOF

    cat << 'EOF' > /home/user/queries.csv
user_id,query_text
101,how to learn C programming
102,data science tutorial for absolute beginners
103,what is tokenization in nlp
104,fastest way to compile
105,best bash commands for data analysis
106,advanced feature engineering techniques
107,random text string
EOF

    chmod -R 777 /home/user
