#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make wget tar
    pip3 install pytest

    mkdir -p /app
    cd /app
    wget -qO- https://downloads.sourceforge.net/project/libcsv/libcsv/libcsv-3.0.3/libcsv-3.0.3.tar.gz | tar xz

    cd /app/libcsv-3.0.3
    ./configure

    # Introduce perturbations
    if grep -q "size_t cb_length;" libcsv.c; then
        sed -i 's/size_t cb_length;/sizet cb_length;/g' libcsv.c
    else
        sed -i '45i sizet cb_length;' libcsv.c
    fi

    if grep -q "^CFLAGS =" Makefile; then
        sed -i 's/^CFLAGS =.*/& -Werror=fake-flag/' Makefile
    else
        echo "CFLAGS += -Werror=fake-flag" >> Makefile
    fi

    # Create corpora
    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/batch1.csv
query_id,edge_pattern
1,A:B;B:C;C:D
2,X1:Y1
3,NODE:M1;M1:M2;M2:M3;M3:NODE
EOF

    cat << 'EOF' > /app/corpus/clean/batch2.csv
query_id,edge_pattern
1,ROOT:A;ROOT:B;ROOT:C
2,A1:A2;A2:A3;A2:A4
EOF

    cat << 'EOF' > /app/corpus/evil/batch1.csv
query_id,edge_pattern
1,A:B;B:C
2,X:Y;A:B
EOF

    cat << 'EOF' > /app/corpus/evil/batch2.csv
query_id,edge_pattern
1,A:B;B:C;C:D
2,N1:N2;N2:N3;N3:N1;M1:M2
EOF

    # Set up user and permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
