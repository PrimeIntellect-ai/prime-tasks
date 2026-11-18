#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app/vendor/csv_lib
    cat << 'EOF' > /app/vendor/csv_lib/csv.h
#ifndef CSV_H
#define CSV_H

#include <iostream>
#include <fstream>
#include <sstream>

// Deliberate bug: missing string and vector headers
namespace csv {
    class Parser {
    public:
        Parser() {}
    };
}

#endif // CSV_H
EOF

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Clean corpus
    for i in 1 2 3 4 5; do
        cat << 'EOF' > /app/corpus/clean/file${i}.csv
timestamp,AAPL_price,AAPL_vol,MSFT_price,MSFT_vol
1000,150.0,100,300.0,200
1001,151.0,150,301.0,250
1002,152.0,100,299.0,300
EOF
    done

    # Evil corpus
    for i in 1 2 3 4 5; do
        cat << 'EOF' > /app/corpus/evil/file${i}.csv
timestamp,AAPL_price,AAPL_vol,MSFT_price,MSFT_vol
1000,150.0,100,300.0,200
1001,151.0,150,301.0,250
1002,152.0,100,299.0,300
EOF
    done

    # Inject bad bytes into evil corpus
    printf '\x80' >> /app/corpus/evil/file1.csv
    printf '\x00' >> /app/corpus/evil/file2.csv
    sed -i 's/150.0/150.0\x80/' /app/corpus/evil/file3.csv
    sed -i 's/MSFT/MSFT\x00/' /app/corpus/evil/file4.csv
    printf '1003,153.0,100,298.0,300\x80\n' >> /app/corpus/evil/file5.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
