#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/authors.csv
author_id,name
1,Alice
2,Bob
3,Charlie
4,Diana
5,Eve
6,Frank
EOF

    cat << 'EOF' > /home/user/data/papers.csv
paper_id,title,domain,citation_count
101,AI Foundations,AI,100
102,Neural Nets,AI,50
103,DB Systems,DB,200
104,Vision AI,AI,10
105,Graph Theory,Math,300
106,AI Ethics,AI,80
EOF

    cat << 'EOF' > /home/user/data/authors_papers.csv
author_id,paper_id
1,101
2,101
1,102
3,102
4,103
2,104
5,104
6,105
1,106
6,106
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
