#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/docs
    mkdir -p /home/user/processed

    cat << 'EOF' > /home/user/data/stopwords.txt
is
a
this
be
that
the
of
to
and
in
EOF

    cat << 'EOF' > /home/user/data/metadata.tsv
docA	2023	tech
docB	2023	sci
docC	2022	tech
docD	2022	sci
EOF

    cat << 'EOF' > /home/user/data/docs/docA.txt
Hello world! This is a test 2023.
EOF

    cat << 'EOF' > /home/user/data/docs/docB.txt
Data Science is fun. Data data data.
EOF

    cat << 'EOF' > /home/user/data/docs/docC.txt
Stopwords should be removed. Is that right?
EOF

    chmod -R 777 /home/user
