#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_data.csv
ID,Store_ID,Customers,Sales,Promo
1,1,100,1500.50,1
2,2,200,3200.00,0
3,1,NA,NA,1
4,1,120,1800.00,1
5,2,210,3300.00,0
6,3,50,800.00,0
7,2,NA,3400.00,1
8,3,60,950.00,1
EOF

    cat << 'EOF' > /home/user/analyze.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <cmath>
#include <iomanip>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc < 2) {
        cerr << "Usage: " << argv[0] << " <csv_file>" << endl;
        return 1;
    }

    ifstream file(argv[1]);
    string line;

    map<int, vector<double>> store_sales;
    vector<double> customers, sales;

    // BUG: Does not skip header
    while (getline(file, line)) {
        stringstream ss(line);
        string item;
        vector<string> tokens;
        while (getline(ss, item, ',')) {
            tokens.push_back(item);
        }

        if (tokens.size() == 5) {
            try {
                int store_id = stoi(tokens[1]);
                double cust = stod(tokens[2]);
                double sale = stod(tokens[3]);

                store_sales[store_id].push_back(sale);
                customers.push_back(cust);
                sales.push_back(sale);
            } catch (...) {
                // Silently inject NaNs on failure (e.g., reading header)
                store_sales[0].push_back(NAN);
                customers.push_back(NAN);
                sales.push_back(NAN);
            }
        }
    }

    // Calculate global beta
    double mean_c = 0, mean_s = 0;
    for (double c : customers) mean_c += c;
    for (double s : sales) mean_s += s;
    mean_c /= customers.size();
    mean_s /= sales.size();

    double num = 0, den = 0;
    for (size_t i = 0; i < customers.size(); i++) {
        num += (customers[i] - mean_c) * (sales[i] - mean_s);
        den += (customers[i] - mean_c) * (customers[i] - mean_c);
    }
    double beta = num / den;

    ofstream out("/home/user/results.txt");
    out << fixed << setprecision(2);
    out << "Global Beta: " << beta << "\n";

    for (auto const& [store, s_list] : store_sales) {
        if (store == 0) continue; // Skip the error bin
        double sum = 0;
        for (double s : s_list) sum += s;
        out << "Store " << store << " Avg Sales: " << sum / s_list.size() << "\n";
    }
    out.close();

    return 0;
}
EOF

    chmod -R 777 /home/user
