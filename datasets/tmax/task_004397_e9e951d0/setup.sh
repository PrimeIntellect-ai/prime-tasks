#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/dataset.csv
ID,F1,F2,F3,F4
1,10,20,,5
2,15,22,1,6
3,12,18,,4
EOF

    cat << 'EOF' > /home/user/process.sh
#!/bin/bash
# Dimensionality reduction: keep only complete columns (ID, F1, F2, F4)
cut -d',' -f1,2,3,5 /home/user/dataset.csv > /home/user/temp.csv

# Inference
# Bug 1: Missing -F',' causing math on whole lines
# Bug 2: sort -R breaks reproducibility
awk 'NR>1 {print $1 "," $2*0.5 + $3*1.2 - $4}' /home/user/temp.csv | sort -R > /home/user/predictions.csv
EOF
    chmod +x /home/user/process.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
