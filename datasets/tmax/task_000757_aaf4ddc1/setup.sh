#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make gdb
    pip3 install pytest

    mkdir -p /home/user/data_processor

    cat << 'EOF' > /home/user/data_processor/data.csv
id,name,score
1,Alice,45
2,Bob,85
3,Charlie,90
4,Dave,60
EOF

    cat << 'EOF' > /home/user/data_processor/Makefile
all:
	gcc main.cpp -o process_data
EOF

    cat << 'EOF' > /home/user/data_processor/main.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cassert>

struct Record {
    int id;
    std::string name;
    int score;
};

int main() {
    std::ifstream file("/home/user/data_processor/data.csv");
    if (!file.is_open()) {
        std::cerr << "Failed to open file." << std::endl;
        return 1;
    }

    std::vector<Record*> records;
    std::string line;

    // Reads all lines, including header
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string id_str, name, score_str;
        std::getline(ss, id_str, ',');
        std::getline(ss, name, ',');
        std::getline(ss, score_str, ',');

        int id = 0, score = 0;
        try {
            id = std::stoi(id_str);
            score = std::stoi(score_str);
        } catch(...) {
            // Header parsing falls here, adding a dummy record
            records.push_back(new Record{-1, "HEADER", -1});
            continue;
        }
        records.push_back(new Record{id, name, score});
    }

    // The data file has exactly 4 valid data rows. 
    // This will fail because the header adds a 5th record.
    assert(records.size() == 4);

    int sum = 0;
    int count = 0;

    // Out of bounds bug (<= instead of <)
    for (size_t i = 0; i <= records.size(); ++i) {
        if (records[i]->score > 50) {
            sum += records[i]->score;
            count++;
        }
    }

    if (count == 0) return 1;

    int avg = sum / count;

    std::ofstream out("/home/user/result.txt");
    out << "Average: " << avg << std::endl;

    for(auto r : records) delete r;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
