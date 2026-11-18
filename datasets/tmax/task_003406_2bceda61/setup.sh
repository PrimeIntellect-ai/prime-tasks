#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang
    pip3 install pytest

    # Clone bluemonday and perturb go.mod
    mkdir -p /app/vendored
    git clone https://github.com/microcosm-cc/bluemonday.git /app/vendored/bluemonday
    cd /app/vendored/bluemonday
    git checkout v1.0.26
    sed -i 's/module github.com\/microcosm-cc\/bluemonday/module github.com\/microcosm-cc\/bluemondayy/g' go.mod

    # Setup corpora
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/corpora/clean/doc1.txt
This is a perfectly normal sentence with more than ten characters.
EOF

    cat << 'EOF' > /home/user/corpora/clean/doc2.txt
Another fantastic piece of training data for our embeddings.
EOF

    cat << 'EOF' > /home/user/corpora/evil/evil1.txt
<h1>Hi</h1>
EOF

    cat << 'EOF' > /home/user/corpora/evil/evil2.txt
<script>alert('xss');</script>
EOF

    cat << 'EOF' > /home/user/corpora/evil/evil3.txt
This is long enough but it contains REJECT_SPAM so it should be blocked.
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline
    chmod -R 777 /home/user
    chmod -R 777 /app
