#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
id,feature1,feature2,target
1,0.12,0.84,10.5
2,0.34,0.11,9.2
3,0.55,0.44,11.1
4,0.76,0.32,8.8
5,0.91,0.55,10.0
6,0.22,0.66,9.5
7,0.44,0.77,10.2
8,0.66,0.88,11.5
9,0.88,0.99,12.0
10,0.11,0.22,8.5
11,0.23,0.33,9.1
12,0.45,0.56,10.8
13,0.67,0.78,11.2
14,0.89,0.12,9.9
15,0.33,0.45,10.3
EOF

    awk -F, 'NR>1 {print $4}' /home/user/data.csv | awk '
    BEGIN { srand(42) }
    { val[NR] = $1 }
    END {
      N = NR
      for (iter=1; iter<=1000; iter++) {
        sum = 0
        for (i=1; i<=N; i++) {
            idx = int(rand() * N) + 1
            sum += val[idx]
        }
        printf "%.6f\n", sum / N
      }
    }' | sort -n > /home/user/expected_means.txt

    sed -n '25p' /home/user/expected_means.txt | awk '{printf "%.4f,", $1}' > /home/user/expected_ci.txt
    sed -n '975p' /home/user/expected_means.txt | awk '{printf "%.4f\n", $1}' >> /home/user/expected_ci.txt
    sed -i ':a;N;$!ba;s/,\n/,/g' /home/user/expected_ci.txt

    chmod -R 777 /home/user
