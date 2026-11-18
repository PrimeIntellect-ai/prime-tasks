#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/project/data
    mkdir -p /home/user/project/src
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/project/data/users.csv
user_id,name
1,Alice
2,Bob
3,Charlie
4,Diana
5,Eve
6,Frank
EOF

    cat << 'EOF' > /home/user/project/data/friends.csv
user_id_1,user_id_2
1,2
2,3
1,4
5,6
EOF

    cat << 'EOF' > /home/user/project/data/purchases.csv
user_id,product_id
1,P1
2,P1
4,P1
5,P2
6,P2
1,P2
1,P3
3,P3
2,P4
3,P4
1,P5
2,P5
3,P5
4,P5
EOF

    cat << 'EOF' > /home/user/project/Makefile
CXX = g++
CXXFLAGS = -std=c++17 -O2

all: analyzer

analyzer: src/analyzer.cpp
	$(CXX) $(CXXFLAGS) -o analyzer src/analyzer.cpp

clean:
	rm -f analyzer
EOF

    cat << 'EOF' > /home/user/project/src/analyzer.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <map>
#include <set>
#include <algorithm>
#include <sstream>

using namespace std;

int main() {
    // Read purchases
    map<string, vector<string>> product_users;
    ifstream p_file("data/purchases.csv");
    string line;
    getline(p_file, line); // skip header
    while (getline(p_file, line)) {
        stringstream ss(line);
        string uid, pid;
        getline(ss, uid, ',');
        getline(ss, pid, ',');
        product_users[pid].push_back(uid);
    }

    // Read friends
    // BUG: The previous engineer loaded this but never actually used it to filter!
    set<pair<string, string>> friends;
    ifstream f_file("data/friends.csv");
    getline(f_file, line); // skip header
    while (getline(f_file, line)) {
        stringstream ss(line);
        string u1, u2;
        getline(ss, u1, ',');
        getline(ss, u2, ',');
        friends.insert({u1, u2});
        friends.insert({u2, u1});
    }

    vector<pair<string, int>> results;

    for (auto const& [pid, users] : product_users) {
        int count = 0;
        // BUG: Implicit cross join without checking friendship
        for (size_t i = 0; i < users.size(); ++i) {
            for (size_t j = i + 1; j < users.size(); ++j) {
                // Incorrectly counting all pairs who bought the product
                count++;
            }
        }
        if (count > 0) {
            results.push_back({pid, count});
        }
    }

    // Sort descending by count, ascending by product_id
    sort(results.begin(), results.end(), [](const pair<string, int>& a, const pair<string, int>& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    });

    ofstream out_file("/home/user/output/report.csv");
    for (size_t i = 0; i < min((size_t)4, results.size()); ++i) {
        out_file << results[i].first << "," << results[i].second << "\n";
    }
    out_file.close();

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
