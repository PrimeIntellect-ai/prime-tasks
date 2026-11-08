#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install pytest

    mkdir -p /home/user/data_pipeline

    cat << 'EOF' > /home/user/data_pipeline/vectors.csv
ID,V1,V2,V3
target_1,10,20,30
item_A,12,19,32
item_B,100,200,300
item_C,9,21,29
item_D,15,15,35
item_E,10,20,31
EOF

    cat << 'EOF' > /home/user/data_pipeline/recommend.sh
#!/bin/bash
TARGET=$1
OUTPUT=$2

# Buggy script: 
# 1. Doesn't compute absolute value
# 2. Doesn't sort numerically (-n)
# 3. Doesn't exclude target

TARGET_VARS=$(grep "^$TARGET," /home/user/data_pipeline/vectors.csv)
T_V1=$(echo $TARGET_VARS | cut -d',' -f2)
T_V2=$(echo $TARGET_VARS | cut -d',' -f3)
T_V3=$(echo $TARGET_VARS | cut -d',' -f4)

awk -F',' -v t1="$T_V1" -v t2="$T_V2" -v t3="$T_V3" '
NR>1 {
    dist = ($2 - t1) + ($3 - t2) + ($4 - t3)
    print dist, $1
}' /home/user/data_pipeline/vectors.csv | sort | head -n 2 | awk '{print $2}' > "$OUTPUT"
EOF

    chmod +x /home/user/data_pipeline/recommend.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
