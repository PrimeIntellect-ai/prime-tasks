#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make binutils
    pip3 install pytest

    mkdir -p /app/data/clean /app/data/evil
    mkdir -p /app/test_data/clean /app/test_data/evil

    # Create the legacy_embedder source
    cat << 'EOF' > /tmp/embedder.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <cmath>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    ifstream in(argv[1]);
    if (!in) return 1;
    string content((istreambuf_iterator<char>(in)), istreambuf_iterator<char>());

    bool corrupt = content.find("CORRUPT") != string::npos;
    bool large = content.find("LARGE") != string::npos;

    vector<double> vec(128, 0.1);
    if (corrupt) {
        vec[0] = NAN;
    } else if (large) {
        for(int i=0; i<128; ++i) vec[i] = 1.0;
    } else {
        for(int i=0; i<128; ++i) vec[i] = 0.5;
    }

    for(int i=0; i<128; ++i) {
        cout << vec[i] << (i == 127 ? "" : " ");
    }
    cout << endl;
    return 0;
}
EOF

    g++ -O2 /tmp/embedder.cpp -o /app/legacy_embedder
    strip /app/legacy_embedder
    rm /tmp/embedder.cpp

    # Create sample and test files
    echo "This is a clean file." > /app/data/clean/file1.txt
    echo "This is a CORRUPT file." > /app/data/evil/file1.txt
    echo "This is a LARGE file." > /app/data/evil/file2.txt

    echo "Another clean file." > /app/test_data/clean/test1.txt
    echo "Another CORRUPT file." > /app/test_data/evil/test1.txt
    echo "Another LARGE file." > /app/test_data/evil/test2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
