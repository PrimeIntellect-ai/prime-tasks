#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/iam_edges.tsv
auditor	billing
billing	compliance
compliance	auditor
billing	external
dev	qa
qa	staging
staging	dev
staging	prod
prod	sysadmin
sysadmin	ops
ops	sec
sec	net
net	sysadmin
user	guest
guest	anon
EOF

    chmod +x /home/user/iam_edges.tsv
    chmod -R 777 /home/user
