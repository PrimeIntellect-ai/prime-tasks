#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest pandas numpy scikit-learn scipy

    mkdir -p /app /home/user

    # Create the C++ source for the binary
    cat << 'EOF' > /tmp/evaluator.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <vector>
#include <algorithm>

double calculate_score(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), ::tolower);
    double score = 1.0;
    std::stringstream ss(text);
    std::string word;
    while (ss >> word) {
        if (word.find("error") != std::string::npos) score += 5.0;
        else if (word.find("fail") != std::string::npos) score += 3.5;
        else if (word.find("warning") != std::string::npos) score += 1.5;
        else if (word.find("timeout") != std::string::npos) score += 4.0;
        else if (word.find("success") != std::string::npos) score -= 2.0;
    }
    return score;
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <input.csv>" << std::endl;
        return 1;
    }
    std::ifstream file(argv[1]);
    std::string line;
    std::getline(file, line); // skip header
    std::cout << "log_id,risk_score\n";
    while (std::getline(file, line)) {
        size_t pos = line.find(',');
        if (pos != std::string::npos) {
            std::string id = line.substr(0, pos);
            std::string text = line.substr(pos + 1);
            std::cout << id << "," << calculate_score(text) << "\n";
        }
    }
    return 0;
}
EOF

    # Compile and strip the binary
    g++ -O3 /tmp/evaluator.cpp -o /app/risk_evaluator
    strip -s /app/risk_evaluator
    chmod +x /app/risk_evaluator

    # Generate training data
    python3 -c '
import random
import csv

words = [
    "error", "fail", "warning", "timeout", "success", 
    "system", "startup", "database", "connection", "disk", 
    "usage", "high", "user", "login", "memory", 
    "allocation", "process", "network", "critical"
]

with open("/home/user/logs.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["log_id", "message"])
    for i in range(1, 1001):
        msg = " ".join(random.choices(words, k=random.randint(2, 8)))
        writer.writerow([i, msg])
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
