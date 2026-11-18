#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk locales
    pip3 install pytest

    # Generate the locale used in the buggy script so it actually triggers the bug
    locale-gen fr_FR.UTF-8

    mkdir -p /home/user

    cat << 'EOF' > /home/user/embeddings.csv
ID,v1,v2,v3,v4,v5
E01,0.1,0.2,0.1,0.0,0.1
E02,0.5,0.5,0.5,0.5,0.5
E03,1.0,1.2,0.9,1.1,1.0
E04,2.0,2.0,2.0,2.0,2.0
E05,0.0,0.1,0.0,0.1,0.0
E06,3.0,0.0,0.0,0.0,0.0
E07,0.8,0.8,0.8,0.8,0.8
E08,0.3,0.3,0.3,0.3,0.3
E09,1.5,1.5,1.5,1.5,1.5
E10,0.1,0.9,0.1,0.1,0.1
E11,0.5,0.6,0.5,0.4,0.5
E12,2.5,2.5,2.5,2.5,2.5
E13,0.2,0.2,0.2,0.2,0.2
EOF

    cat << 'EOF' > /home/user/val_labels.csv
ID,is_outlier
E01,0
E02,0
E03,0
E04,1
E05,0
E06,1
E07,0
E08,0
E09,1
E10,0
EOF

    cat << 'EOF' > /home/user/filter_outliers.sh
#!/bin/bash
export LC_NUMERIC=fr_FR.UTF-8
THRESHOLD=$1

awk -v thresh="$THRESHOLD" -F, '
NR>1 {
    sum=0;
    for(i=2; i<=NF; i++) sum += $i*$i;
    norm = sqrt(sum);
    if(norm < thresh) print $1;
}' /home/user/embeddings.csv
EOF

    chmod +x /home/user/filter_outliers.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
