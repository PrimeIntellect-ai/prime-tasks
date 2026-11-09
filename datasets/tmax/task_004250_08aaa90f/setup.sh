#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go git
    pip3 install pytest

    # Clone the vendored package
    mkdir -p /app
    git clone --branch v0.23.0 https://github.com/dominikbraun/graph.git /app/graph

    # Apply perturbation
    sed -i 's/package graph/package grraph/' /app/graph/graph.go

    # Create corpora directories
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Create clean CSVs
    cat <<EOF > /home/user/corpora/clean/1.csv
id,parent_id
A,B
B,C
EOF
    cat <<EOF > /home/user/corpora/clean/2.csv
id,parent_id
1,2
2,3
EOF
    cat <<EOF > /home/user/corpora/clean/3.csv
id,parent_id
X,Y
Y,Z
EOF
    cat <<EOF > /home/user/corpora/clean/4.csv
id,parent_id
M,N
N,O
EOF
    cat <<EOF > /home/user/corpora/clean/5.csv
id,parent_id
foo,bar
bar,baz
EOF

    # Create evil CSVs
    cat <<EOF > /home/user/corpora/evil/1.csv
id,parent_id
A,B
B,C
C,A
EOF
    cat <<EOF > /home/user/corpora/evil/2.csv
id,parent_id
1,2
2,3
3,1
EOF
    cat <<EOF > /home/user/corpora/evil/3.csv
id,parent_id
X,Y
Y,X
EOF
    cat <<EOF > /home/user/corpora/evil/4.csv
id,parent_id
M,N
N,O
O,M
EOF
    cat <<EOF > /home/user/corpora/evil/5.csv
id,parent_id
foo,bar
bar,baz
baz,foo
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
