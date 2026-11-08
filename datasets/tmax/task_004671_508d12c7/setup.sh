#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk sed grep coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/corpus.txt
The quick brown fox.
The fast brown dog!
EOF

    cat << 'EOF' > /home/user/test.txt
The quick brown dog.
A fast fox!
EOF

    cat << 'EOF' > /home/user/expected_model.tsv
brown	dog	0.2500
brown	fox	0.2500
fast	brown	0.2857
quick	brown	0.2857
the	fast	0.2500
the	quick	0.2500
EOF

    cat << 'EOF' > /home/user/expected_scores.tsv
1	-4.0253
2	-3.7377
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
