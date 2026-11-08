#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/documents.csv
id,text,label
1,this is a test,0
2,another document with more words in it,1
3,short text,0
4,the longest document in the entire dataset with many words,1
5,hello world,0
6,machine learning is fun,1
7,data science leakage,0
8,bash scripting for data preparation,1
9,awk is powerful,0
10,testing data leakage scenarios,1
EOF

    cat << 'EOF' > /home/user/prepare_dataset.sh
#!/bin/bash
# Buggy prepare_dataset.sh

# Leakage: computing max words from the entire dataset
MAX_WORDS=$(awk -F',' 'NR>1 {print NF}' /home/user/data/documents.csv | sort -nr | head -n1)

total_lines=$(($(wc -l < /home/user/data/documents.csv) - 1))
train_lines=$((total_lines * 80 / 100))

# Split
tail -n +2 /home/user/data/documents.csv | head -n $train_lines > /home/user/data/train_raw.csv
tail -n +2 /home/user/data/documents.csv | tail -n +$((train_lines + 1)) > /home/user/data/test_raw.csv

# Normalize
awk -v max=$MAX_WORDS -F',' '{wc=split($2,a," "); print $1, wc/max, $3}' /home/user/data/train_raw.csv > /home/user/data/train_normalized.csv
awk -v max=$MAX_WORDS -F',' '{wc=split($2,a," "); print $1, wc/max, $3}' /home/user/data/test_raw.csv > /home/user/data/test_normalized.csv
EOF
    chmod +x /home/user/prepare_dataset.sh

    chmod -R 777 /home/user
