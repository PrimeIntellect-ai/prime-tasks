#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > fasta_stats.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <fasta_file>\n";
        return 1;
    }

    std::ifstream file(argv[1]);
    std::string line, id;
    int gc = 0, total = 0;

    while (std::getline(file, line)) {
        if (line.empty()) continue;
        if (line[0] == '>') {
            if (!id.empty() && total > 0) {
                std::cout << id << "\t" << std::fixed << std::setprecision(2) << (100.0 * gc / total) << "\n";
            }
            id = line.substr(1);
            gc = 0;
            total = 0;
        } else {
            for (char c : line) {
                if (c == 'G' || c == 'C' || c == 'g' || c == 'c') gc++;
                if (isalpha(c)) total++;
            }
        }
    }
    if (!id.empty() && total > 0) {
        std::cout << id << "\t" << std::fixed << std::setprecision(2) << (100.0 * gc / total) << "\n";
    }
    return 0;
}
EOF

    cat << 'EOF' > groupA.fasta
>seqA1
ATATATATGCATATAT
>seqA2
GCGCATATATATATAT
>seqA3
ATATATATATATATAT
EOF

    cat << 'EOF' > groupB.fasta
>seqB1
GCGCGCGCGCGCATAT
>seqB2
GCGCGCGCGCGCGCGC
>seqB3
GCGCATATGCGCGCGC
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
