#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
id,abstract,citations
doc1,Machine learning is fascinating,10
doc2,Deep learning models are large,100
doc3,Data science extracts value from data,5
doc4,A fascinating look at neural networks,45
doc5,Learning from data is a core concept,12
doc6,Large language models perform well,200
doc7,Statistics is the foundation of data analysis,8
doc8,Neural networks require massive compute,150
EOF

    chmod -R 777 /home/user
