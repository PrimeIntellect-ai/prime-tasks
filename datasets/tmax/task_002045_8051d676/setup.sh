#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_data.csv
id,text,value
1.0,"The quick brown fox jumps over the lazy dog",15.5
2.0,"Data science involves statistics and algorithms",22.1
,"This row has a missing ID and should be dropped",10.0
4.0,"Machine learning models require good data",18.3
5.0,"The quick brown fox is quick",12.4
6.0,"Algorithms and data structures are fundamental",25.0
7.0,"Statistics is the grammar of science",21.8
EOF

    cat << 'EOF' > /home/user/predictions.json
{
  "1": 0.8,
  "2": 0.9,
  "5": 0.4,
  "6": 0.7
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
