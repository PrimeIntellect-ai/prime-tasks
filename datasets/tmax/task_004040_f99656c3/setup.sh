#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak g++
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak -w /app/dictation.wav "Please ensure all extracted files are safely placed into the target directory named: alpha_docs_2024"

    # Create oracle program
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sstream>

using namespace std;

void process_path(const string& path) {
    vector<string> stack;
    string token;
    stringstream ss(path);
    while (getline(ss, token, '/')) {
        if (token == "" || token == ".") continue;
        if (token == "..") {
            if (stack.empty()) {
                cout << "INVALID\n";
                return;
            }
            stack.pop_back();
        } else {
            stack.push_back(token);
        }
    }

    cout << "alpha_docs_2024/";
    for (size_t i = 0; i < stack.size(); ++i) {
        cout << stack[i];
        if (i < stack.size() - 1) cout << "/";
    }
    cout << "\n";
}

int main() {
    string line;
    while (getline(cin, line)) {
        process_path(line);
    }
    return 0;
}
EOF

    g++ -O2 /app/oracle.cpp -o /app/oracle_path_resolver
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
