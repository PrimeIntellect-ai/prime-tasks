#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/data

    # Generate voicemail
    espeak -w /app/voicemail.wav "Hi, it's Alice. I left the data exports in the data directory. The users file has user_id, name, and region. The transactions file has tx_id, user_id, product_id, and amount. The products file has product_id, product_name, and category. I need you to write a C plus plus program that takes two command line arguments: first the region, then the category. It should join these tables, filter for the given region and category, and calculate the total amount spent per user ID. Print the result as a CSV to standard output with the header user_id,total_amount, followed by the data rows sorted by user ID ascending. Keep amounts to two decimal places."

    # Create CSV files
    cat << 'EOF' > /home/user/data/users.csv
user_id,name,region
1,Alice,North
2,Bob,South
3,Charlie,North
4,Diana,East
EOF

    cat << 'EOF' > /home/user/data/products.csv
product_id,product_name,category
101,Laptop,Electronics
102,T-Shirt,Clothing
103,Novel,Books
104,Phone,Electronics
EOF

    cat << 'EOF' > /home/user/data/transactions.csv
tx_id,user_id,product_id,amount
1001,1,101,1200.50
1002,2,102,25.00
1003,1,104,800.00
1004,3,101,1200.50
1005,4,103,15.75
EOF

    # Create oracle C++ program
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <iomanip>
#include <algorithm>

using namespace std;

struct User { string region; };
struct Product { string category; };

int main(int argc, char* argv[]) {
    if (argc < 3) return 1;
    string target_region = argv[1];
    string target_category = argv[2];

    map<string, User> users;
    ifstream ufile("/home/user/data/users.csv");
    string line;
    getline(ufile, line);
    while (getline(ufile, line)) {
        if(line.empty()) continue;
        stringstream ss(line);
        string uid, name, region;
        getline(ss, uid, ',');
        getline(ss, name, ',');
        getline(ss, region, ',');
        users[uid] = {region};
    }

    map<string, Product> products;
    ifstream pfile("/home/user/data/products.csv");
    getline(pfile, line);
    while (getline(pfile, line)) {
        if(line.empty()) continue;
        stringstream ss(line);
        string pid, pname, cat;
        getline(ss, pid, ',');
        getline(ss, pname, ',');
        getline(ss, cat, ',');
        products[pid] = {cat};
    }

    map<string, double> totals;
    ifstream tfile("/home/user/data/transactions.csv");
    getline(tfile, line);
    while (getline(tfile, line)) {
        if(line.empty()) continue;
        stringstream ss(line);
        string tid, uid, pid, amt_str;
        getline(ss, tid, ',');
        getline(ss, uid, ',');
        getline(ss, pid, ',');
        getline(ss, amt_str, ',');
        double amt = stod(amt_str);

        if (users.count(uid) && products.count(pid)) {
            if (users[uid].region == target_region && products[pid].category == target_category) {
                totals[uid] += amt;
            }
        }
    }

    cout << "user_id,total_amount\n";
    vector<pair<int, double>> sorted_totals;
    for (auto& kv : totals) {
        sorted_totals.push_back({stoi(kv.first), kv.second});
    }
    sort(sorted_totals.begin(), sorted_totals.end());

    for (auto& kv : sorted_totals) {
        cout << kv.first << "," << fixed << setprecision(2) << kv.second << "\n";
    }

    return 0;
}
EOF

    g++ -O3 -o /app/oracle_query_engine /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
