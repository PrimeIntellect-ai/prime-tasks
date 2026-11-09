#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create reproducible random seed for shuf
    printf '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20' > /home/user/seed.dat

    # Create features.csv
    cat << 'EOF' > /home/user/features.csv
1,10
2,
3,80
4,20
5,
6,90
7,40
8,
9,60
10,100
EOF

    # Create targets.csv
    cat << 'EOF' > /home/user/targets.csv
1,0
2,1
3,1
4,0
5,1
6,1
7,0
8,0
9,1
10,1
EOF

    # Create original buggy pipeline.sh
    cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash
# 1. Join data
join -t, -1 1 -2 1 <(sort -t, -k1,1 /home/user/features.csv) <(sort -t, -k1,1 /home/user/targets.csv) > /home/user/joined.csv

# 2. DATA LEAK: Compute global mean of feature (column 2)
mean=$(awk -F, '$2 != "" {sum+=$2; count++} END {print sum/count}' /home/user/joined.csv)

# 3. Impute missing values with mean
awk -F, -v m="$mean" 'BEGIN{OFS=","} {if($2=="") $2=m; print $0}' /home/user/joined.csv > /home/user/imputed.csv

# 4. Split: 80% train, 20% test
total=$(wc -l < /home/user/imputed.csv)
train_n=$((total * 80 / 100))
shuf --random-source=/home/user/seed.dat /home/user/imputed.csv > /home/user/shuffled.csv
head -n "$train_n" /home/user/shuffled.csv > /home/user/train.csv
tail -n +$((train_n + 1)) /home/user/shuffled.csv > /home/user/test.csv

# 5. Evaluate (Average target where feature > 50)
awk -F, '$2 > 50 {sum+=$3; count++} END {if(count>0) print sum/count; else print 0}' /home/user/test.csv > /home/user/metric.txt
EOF

    chmod +x /home/user/pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
