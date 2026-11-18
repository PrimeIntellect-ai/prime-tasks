#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/batch_C.csv
x,y
5,6.2
6,7.4
EOF

    cat << 'EOF' > /home/user/data/batch_A.csv
x,y
1,1.5
2,2.6
EOF

    cat << 'EOF' > /home/user/data/batch_B.csv
x,y
3,3.8
4,5.1
EOF

    cat << 'EOF' > /home/user/process_binding.sh
#!/bin/bash
# Buggy: arbitrary order of file processing causes non-reproducible awk floating point accumulation
find /home/user/data -name "*.csv" -print0 | xargs -0 cat | grep -v "^x,y" | awk -F, '{
    sum_x+=$1; sum_y+=$2; sum_xy+=$1*$2; sum_xx+=$1*$1; n++
} END {
    slope=(n*sum_xy - sum_x*sum_y)/(n*sum_xx - sum_x*sum_x);
    printf "%.5f\n", slope
}'
EOF
    chmod +x /home/user/process_binding.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
