#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/authors.csv
1,Alice,Physics,2010
2,Bob,Physics,2012
3,Charlie,Math,2015
4,Diana,ComputerScience,2018
5,Eve,Math,2020
6,Frank,Biology,2011
7,Grace,ComputerScience,2019
8,Heidi,Physics,2021
9,Ivan,Chemistry,2017
10,Judy,Biology,2013
EOF

    cat << 'EOF' > /home/user/coauthors.csv
1,2,5
2,3,2
3,4,1
4,5,3
2,6,1
6,7,4
1,8,2
7,9,1
6,10,3
10,3,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
