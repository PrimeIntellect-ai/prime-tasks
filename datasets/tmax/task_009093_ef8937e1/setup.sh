#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential wget tar
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/data.csv
10,0.9,0.8,0.7,0.6,0.5
11,0.89,0.81,0.69,0.61,0.52
12,0.1,0.1,0.1,0.1,0.1
13,0.85,0.75,0.75,0.55,0.45
14,0.80,0.80,0.80,0.60,0.50
15,0.0,0.0,0.0,0.0,1.0
16,0.2,0.3,0.4,0.5,0.6
EOF

cat << 'EOF' > /home/user/recommender.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <algorithm>
#include <Eigen/Dense>

using namespace std;
using namespace Eigen;

// BUG: Using int instead of double for embeddings
struct Item {
    int id;
    VectorXi emb; // Should be VectorXd
};

int main(int argc, char** argv) {
    if (argc != 2) {
        cerr << "Usage: ./recommender <target_id>" << endl;
        return 1;
    }
    int target_id = stoi(argv[1]);

    vector<Item> items;
    ifstream file("/home/user/data.csv");
    string line;

    while (getline(file, line)) {
        stringstream ss(line);
        string token;
        Item item;

        getline(ss, token, ',');
        item.id = stoi(token);

        // BUG: Using VectorXi and stoi instead of VectorXd and stod
        item.emb = VectorXi(5);
        for (int i = 0; i < 5; ++i) {
            getline(ss, token, ',');
            item.emb[i] = stoi(token); 
        }
        items.push_back(item);
    }

    Item target_item;
    bool found = false;
    for (const auto& item : items) {
        if (item.id == target_id) {
            target_item = item;
            found = true;
            break;
        }
    }

    if (!found) {
        cerr << "Target ID not found." << endl;
        return 1;
    }

    vector<pair<int, double>> similarities;
    for (const auto& item : items) {
        if (item.id == target_id) continue;

        // Cosine similarity
        double dot = target_item.emb.cast<double>().dot(item.emb.cast<double>());
        double norm1 = target_item.emb.cast<double>().norm();
        double norm2 = item.emb.cast<double>().norm();

        double sim = (norm1 == 0 || norm2 == 0) ? 0 : dot / (norm1 * norm2);
        similarities.push_back({item.id, sim});
    }

    sort(similarities.begin(), similarities.end(), [](const pair<int, double>& a, const pair<int, double>& b) {
        return a.second > b.second;
    });

    ofstream outfile("/home/user/output.txt");
    outfile << target_id << ": " 
            << similarities[0].first << ", " 
            << similarities[1].first << ", " 
            << similarities[2].first << endl;
    outfile.close();

    return 0;
}
EOF

chmod -R 777 /home/user
