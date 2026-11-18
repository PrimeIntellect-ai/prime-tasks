#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/scripts

    # Generate a synthetic raw.csv (100 rows, 3 columns)
    cat << 'EOF' > /home/user/data/raw.csv
10.5,2.1,0
11.2,2.3,0
9.8,1.9,1
10.1,2.0,1
12.5,2.8,0
13.1,3.0,1
9.5,1.8,0
10.8,2.2,1
11.5,2.4,0
10.0,2.1,1
10.5,2.1,0
11.2,2.3,0
9.8,1.9,1
10.1,2.0,1
12.5,2.8,0
13.1,3.0,1
9.5,1.8,0
10.8,2.2,1
11.5,2.4,0
10.0,2.1,1
10.5,2.1,0
11.2,2.3,0
9.8,1.9,1
10.1,2.0,1
12.5,2.8,0
13.1,3.0,1
9.5,1.8,0
10.8,2.2,1
11.5,2.4,0
10.0,2.1,1
10.5,2.1,0
11.2,2.3,0
9.8,1.9,1
10.1,2.0,1
12.5,2.8,0
13.1,3.0,1
9.5,1.8,0
10.8,2.2,1
11.5,2.4,0
10.0,2.1,1
10.5,2.1,0
11.2,2.3,0
9.8,1.9,1
10.1,2.0,1
12.5,2.8,0
13.1,3.0,1
9.5,1.8,0
10.8,2.2,1
11.5,2.4,0
10.0,2.1,1
10.5,2.1,0
11.2,2.3,0
9.8,1.9,1
10.1,2.0,1
12.5,2.8,0
13.1,3.0,1
9.5,1.8,0
10.8,2.2,1
11.5,2.4,0
10.0,2.1,1
10.5,2.1,0
11.2,2.3,0
9.8,1.9,1
10.1,2.0,1
12.5,2.8,0
13.1,3.0,1
9.5,1.8,0
10.8,2.2,1
11.5,2.4,0
10.0,2.1,1
10.5,2.1,0
11.2,2.3,0
9.8,1.9,1
10.1,2.0,1
12.5,2.8,0
13.1,3.0,1
9.5,1.8,0
10.8,2.2,1
11.5,2.4,0
10.0,2.1,1
15.0,4.0,1
14.5,3.8,0
8.0,1.5,1
8.5,1.6,0
16.0,4.5,1
15.5,4.2,0
7.5,1.2,1
7.8,1.4,0
17.0,5.0,1
16.5,4.8,0
15.0,4.0,1
14.5,3.8,0
8.0,1.5,1
8.5,1.6,0
16.0,4.5,1
15.5,4.2,0
7.5,1.2,1
7.8,1.4,0
17.0,5.0,1
16.5,4.8,0
EOF

    # Buggy script setup
    cat << 'EOF' > /home/user/scripts/prepare_data.sh
#!/bin/bash
# BUGGY SCRIPT: Calculates stats over the whole dataset!
awk -F',' '{sum1+=$1; sum2+=$2; sumsq1+=$1*$1; sumsq2+=$2*$2} END {
    mean1=sum1/NR; mean2=sum2/NR; 
    std1=sqrt(sumsq1/NR - mean1*mean1); std2=sqrt(sumsq2/NR - mean2*mean2);
    print mean1, std1, mean2, std2
}' /home/user/data/raw.csv > /tmp/stats.txt

read m1 s1 m2 s2 < /tmp/stats.txt

awk -v m1=$m1 -v s1=$s1 -v m2=$m2 -v s2=$s2 -F',' '{
    printf "%.6f,%.6f,%d\n", ($1-m1)/s1, ($2-m2)/s2, $3
}' /home/user/data/raw.csv > /home/user/data/scaled.csv

head -n 80 /home/user/data/scaled.csv > /home/user/data/train_scaled.csv
tail -n 20 /home/user/data/scaled.csv > /home/user/data/test_scaled.csv
EOF
    chmod +x /home/user/scripts/prepare_data.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
