#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
id,text,feature
1,apple banana,10.0
2,apple orange,12.0
3,banana grape,8.0
4,grape orange,11.0
5,apple kiwi,10.5
6,kiwi mango,9.0
7,mango apple,10.0
8,banana mango,11.5
9,papaya orange,20.0
10,papaya kiwi,22.0
EOF

    cat << 'EOF' > /home/user/prepare_data.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <unordered_map>
#include <iomanip>

using namespace std;

struct Record {
    int id;
    vector<string> tokens;
    double feature;
};

int main() {
    ifstream infile("/home/user/data.csv");
    string line, header;
    getline(infile, header);

    vector<Record> dataset;
    while (getline(infile, line)) {
        stringstream ss(line);
        string id_str, text, feature_str;
        getline(ss, id_str, ',');
        getline(ss, text, ',');
        getline(ss, feature_str, ',');

        Record rec;
        rec.id = stoi(id_str);
        rec.feature = stod(feature_str);

        stringstream ts(text);
        string token;
        while (getline(ts, token, ' ')) {
            rec.tokens.push_back(token);
        }
        dataset.push_back(rec);
    }

    // DATA LEAK: Computing vocab and mean over the entire dataset
    unordered_map<string, int> vocab;
    int vocab_idx = 1;
    double sum = 0.0;

    for (const auto& rec : dataset) {
        for (const auto& w : rec.tokens) {
            if (vocab.find(w) == vocab.end()) {
                vocab[w] = vocab_idx++;
            }
        }
        sum += rec.feature;
    }

    double mean = sum / dataset.size();

    // Split into train (first 8) and test (last 2)
    int train_size = 8;

    ofstream train_out("/home/user/train_features.txt");
    ofstream test_out("/home/user/test_features.txt");

    for (size_t i = 0; i < dataset.size(); ++i) {
        ofstream& out = (i < train_size) ? train_out : test_out;
        out << dataset[i].id << ",";
        for (size_t j = 0; j < dataset[i].tokens.size(); ++j) {
            int tid = vocab.count(dataset[i].tokens[j]) ? vocab[dataset[i].tokens[j]] : 0;
            out << tid << (j + 1 == dataset[i].tokens.size() ? "" : " ");
        }
        out << "," << fixed << setprecision(2) << (dataset[i].feature - mean) << "\n";
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
