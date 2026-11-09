#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gcc
    pip3 install pytest

    mkdir -p /home/user/data/

    cat << 'EOF' > /home/user/data/institutions.tsv
1	University of Toronto	Canada
2	McGill University	Canada
3	MIT	USA
4	University of British Columbia	Canada
5	University of Waterloo	Canada
EOF

    cat << 'EOF' > /home/user/data/authors.tsv
101	Alice	1
102	Bob	2
103	Charlie	3
104	Dave	4
105	Eve	5
106	Frank	1
EOF

    cat << 'EOF' > /home/user/data/publications.tsv
1001	101	Paper A	2015	50
1002	101	Paper B	2009	200
1003	102	Paper C	2012	30
1004	104	Paper D	2018	100
1005	105	Paper E	2011	80
1006	106	Paper F	2020	40
1007	103	Paper G	2019	500
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
