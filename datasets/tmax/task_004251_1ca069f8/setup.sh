#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/bash-datakit
    mkdir -p /app/data/clean
    mkdir -p /app/data/evil

    # Create vendored script with bug
    cat << 'EOF' > /app/vendored/bash-datakit/validate_csv.sh
#!/bin/bash
# validate_csv.sh enforces exactly 3 columns.
awk -F, 'NR==1 {print $0; next} NF==3 {print ""}' "$1"
EOF
    chmod +x /app/vendored/bash-datakit/validate_csv.sh

    # Create training data
    cat << 'EOF' > /app/data/train.csv
user_id,action,geo,is_bot
1,click,US,0
2,scroll,EU,0
3,type,US,0
4,click,ASIA,1
5,click,ASIA,1
6,scroll,ASIA,1
EOF

    # Create clean test data
    cat << 'EOF' > /app/data/clean/test1.csv
user_id,action,geo
10,type,US
11,scroll,EU
12,click,US
EOF

    # Create evil test data
    cat << 'EOF' > /app/data/evil/test2.csv
user_id,action,geo
20,click,ASIA
21,scroll,ASIA
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
