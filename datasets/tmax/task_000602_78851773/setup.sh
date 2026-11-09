#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/eval.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <regex>
#include <unordered_set>
#include <iomanip>
#include <cmath>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc < 2) {
        cout << "Score: 0.00\n";
        return 0;
    }
    ifstream infile(argv[1]);
    if (!infile) {
        cout << "Score: 0.00\n";
        return 0;
    }

    string line;
    regex email_re("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}");
    regex phone_re("\\d{3}-\\d{3}-\\d{4}");

    unordered_set<string> seen;
    vector<int> lengths;

    double score = 1.0;
    int total_lines = 0;
    int errors = 0;

    while (getline(infile, line)) {
        total_lines++;
        if (regex_search(line, email_re)) errors++;
        if (regex_search(line, phone_re)) errors++;

        size_t last_comma = line.find_last_of(',');
        if (last_comma == string::npos) {
            errors++;
            continue;
        }

        string content = line.substr(0, last_comma);
        string avg_str = line.substr(last_comma + 1);

        if (seen.count(content)) errors++;
        seen.insert(content);

        double expected_avg = 0.0;
        int count = 0;
        int sum = 0;
        for (int i = max(0, (int)lengths.size() - 5); i < (int)lengths.size(); ++i) {
            sum += lengths[i];
            count++;
        }
        if (count > 0) expected_avg = (double)sum / count;

        double actual_avg = -1.0;
        try {
            actual_avg = stod(avg_str);
        } catch (...) {
            errors++;
        }

        if (abs(actual_avg - expected_avg) > 0.15) errors++;

        lengths.push_back(content.length());
    }

    if (total_lines == 0) {
        cout << "Score: 0.00\n";
        return 0;
    }

    score = 1.0 - ((double)errors / total_lines);
    if (score < 0.0) score = 0.0;

    cout << "Score: " << fixed << setprecision(2) << score << "\n";
    return 0;
}
EOF

    g++ -O3 -o /app/evaluator /tmp/eval.cpp
    strip --strip-all /app/evaluator
    chmod +x /app/evaluator

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_chats.txt
   HELLO world  user@example.com  
123-456-7890 is my number
Duplicate line
Duplicate line
   another line with 999-999-9999 and test@test.com
EOF

    for i in $(seq 1 10000); do
        echo "Line $i with some extra   spaces and maybe email$i@domain.com and phone 123-456-7890" >> /home/user/raw_chats.txt
    done

    chmod -R 777 /home/user
