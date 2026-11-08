#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb strace binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    cat << 'EOF' > evaluator.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>

void process_query(const std::string& line) {
    std::stringstream ss(line);
    std::string token;
    std::vector<int> vals;
    while(std::getline(ss, token, ',')) {
        vals.push_back(std::stoi(token));
    }
    if (vals.size() >= 3) {
        // Integer division by zero triggers SIGFPE
        volatile int result = (vals[0] * vals[1]) / vals[2];
        std::cout << "Processed: " << result << std::endl;
    }
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream infile(argv[1]);
    std::string line;
    while(std::getline(infile, line)) {
        process_query(line);
    }
    return 0;
}
EOF

    g++ -O0 evaluator.cpp -o math_evaluator
    strip math_evaluator
    rm evaluator.cpp

    for i in {1..1000}; do
        if [ $i -eq 742 ]; then
            echo "45,99,0,12" >> queries.csv
        else
            echo "$RANDOM,$RANDOM,$((RANDOM % 99 + 1)),$RANDOM" >> queries.csv
        fi
    done

    chown -R user:user /home/user/math_evaluator /home/user/queries.csv
    chmod -R 777 /home/user
