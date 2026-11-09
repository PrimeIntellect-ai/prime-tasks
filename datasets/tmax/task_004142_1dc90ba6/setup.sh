#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > docs.csv
doc_id,author
doc_1,Alice
doc_2,Bob
doc_3,Charlie
doc_4,Dave
doc_5,Eve
EOF

    cat << 'EOF' > tokens.csv
doc_id,token_id
doc_1,9007199254740995
doc_3,9007199254740997
doc_4,1048576
doc_5,9007199254740993
EOF

    cat << 'EOF' > buggy_join.py
import pandas as pd

docs = pd.read_csv('/home/user/docs.csv')
tokens = pd.read_csv('/home/user/tokens.csv')

joined = docs.merge(tokens, on='doc_id', how='left')
joined.to_csv('/home/user/bad_output.csv', index=False)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
