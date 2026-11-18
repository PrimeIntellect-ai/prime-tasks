#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
id,f1,f2,y
1,4.0,2.0,8.6
2,,3.0,5.0
3,2.0,5.0,-1.5
4,5.0,,12.0
5,6.0,1.0,13.8
EOF

    cat << 'EOF' > /home/user/etl.sh
#!/bin/bash

# Broken ETL script
awk -F, 'NR>1 {
    pred = 2.5*$2 - 1.2*$3;
    err = pred - $4;
    if (err < 0) err = -err;
    sum_err += err;
    count++;
    print $1 "," pred "," $4 > "/home/user/predictions.csv";
} END {
    if (count > 0) print "MAE=" sum_err/count >> "/home/user/metrics.log";
}' /home/user/data.csv
EOF
    chmod +x /home/user/etl.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
