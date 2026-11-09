#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y imagemagick tesseract-ocr fonts-dejavu-core cargo rustc

    mkdir -p /app/evil_corpus /app/clean_corpus

    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,100 'POISON RULE: Reject record IF account_age < 30 AND amount > 50000.0'" /app/anomaly_rules.png

    cat << 'EOF' > /app/clean_corpus/clean1.csv
transaction_id,split_type,amount,account_age
1,train,45000.0,25
2,test,55000.0,35
3,train,10000.0,10
EOF

    cat << 'EOF' > /app/clean_corpus/clean2.csv
transaction_id,split_type,amount,account_age
4,train,49999.0,29
5,test,60000.0,30
EOF

    cat << 'EOF' > /app/evil_corpus/evil1.csv
transaction_id,split_type,amount,account_age
6,train,15000.0,40
7,test,50001.0,29
8,train,20000.0,50
EOF

    cat << 'EOF' > /app/evil_corpus/evil2.csv
transaction_id,split_type,amount,account_age
9,train,60000.0,20
10,test,10000.0,15
EOF

    cat << 'EOF' > /app/leak_test_input.csv
transaction_id,split_type,amount,account_age
1,train,100.0,10.0
2,train,300.0,30.0
3,test,1000.0,100.0
4,test,5000.0,500.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
