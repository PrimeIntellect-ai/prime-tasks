#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/raw_data/edges.tsv
alice	follows	repoA
bob	follows	repoB
charlie	follows	repoC
alice	follows	repoC
repoA	contains	main.py
repoA	contains	utils.py
repoB	contains	app.js
repoC	contains	index.ts
main.py	imports	requests
utils.py	imports	os
app.js	imports	express
index.ts	imports	lodash
main.py	imports	sys
bob	knows	alice
repoA	forked_from	repoZ
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
