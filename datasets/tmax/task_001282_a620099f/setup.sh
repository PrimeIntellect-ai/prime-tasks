#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc redis-server redis-tools netcat-openbsd
    pip3 install pytest

    mkdir -p /app/tests/corpus/clean
    mkdir -p /app/tests/corpus/evil

    # Create clean corpus
    cat << 'EOF' > /app/tests/corpus/clean/data1.csv
1,45.5,12.2,catA
2,-900.1,0.0,catB
3,1000.0,-1000.0,catC
EOF

    # Create evil corpus
    cat << 'EOF' > /app/tests/corpus/evil/mal1.csv
1,45.5,12.2,catA
4,NaN,10.0,catD
5,1000.1,5.0,catE
6,50.0,50.0,toolongcategoryname
7,10.0,10.0,catF,extra_column
8,drop table,1.0,catG
EOF

    cat << 'EOF' > /app/start_pipeline.sh
#!/bin/bash
# TODO: Start Redis
# TODO: Start netcat listener on port 9000 that pipes through /home/user/sanitizer and into redis-cli
EOF
    chmod +x /app/start_pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
