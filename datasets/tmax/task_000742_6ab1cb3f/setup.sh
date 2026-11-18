#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils sed grep gawk
    pip3 install pytest

    mkdir -p /home/user/data_pipeline

    cat << 'EOF' > /home/user/data_pipeline/data.tsv
id	category	description
1	tech	The quick brown fox jumps over the lazy dog.
2	tech	The dog barks at the fox!
3	science	Science is a systematic enterprise that builds and organizes knowledge.
4	science	The systematic enterprise is systematic.
5	general	A quick test of the pipeline.
EOF

    cat << 'EOF' > /home/user/data_pipeline/process.sh
#!/bin/bash
# Extract description, tokenize, and get top 5 words
# BUG: sed removes all letters instead of keeping them
tail -n +2 data.tsv | cut -f3 | tr '[:upper:]' '[:lower:]' | sed 's/[a-z]//g' | tr ' ' '\n' | grep -v '^$' | sort | uniq -c | sort -nr | head -n 5 > top_words.txt
EOF
    chmod +x /home/user/data_pipeline/process.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
