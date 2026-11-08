#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/data
mkdir -p /home/user/src
mkdir -p /home/user/output

cat << 'EOF' > /home/user/data/documents.csv
id,text,category
1,data science model,A
2,pipeline agent data,B
three,invalid row,C
4,agent model,A
5,data data data,B
invalid,agent,D
EOF

cat << 'EOF' > /home/user/src/pipeline.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cmath>

using namespace std;

// Vocabulary
const vector<string> VOCAB = {"data", "science", "pipeline", "agent", "model"};

vector<int> get_embedding(const string& text) {
    vector<int> emb(VOCAB.size(), 0);
    stringstream ss(text);
    string word;
    while (ss >> word) {
        for (size_t i = 0; i < VOCAB.size(); ++i) {
            if (word == VOCAB[i]) emb[i]++;
        }
    }
    return emb;
}

double cosine_similarity(const vector<int>& a, const vector<int>& b) {
    int dot = 0;
    int norm_a_sq = 0;
    int norm_b_sq = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        dot += a[i] * b[i];
        norm_a_sq += a[i] * a[i];
        norm_b_sq += b[i] * b[i];
    }
    if (norm_a_sq == 0 || norm_b_sq == 0) return 0.0;

    // BUG: integer division here causes results < 1 to become 0.
    double sim = dot / (sqrt(norm_a_sq) * sqrt(norm_b_sq));
    return sim;
}

int main() {
    ifstream file("/home/user/data/documents.csv");
    string line;
    vector<vector<int>> embeddings;

    getline(file, line); // header

    while (getline(file, line)) {
        stringstream ss(line);
        string id_str, text, category;
        getline(ss, id_str, ',');
        getline(ss, text, ',');
        getline(ss, category, ',');

        // BUG: missing schema validation for id_str. Should check if integer.
        // Currently it just parses whatever.
        embeddings.push_back(get_embedding(text));
    }

    double total_sim = 0;
    int pairs = 0;
    for (size_t i = 0; i < embeddings.size(); ++i) {
        for (size_t j = i + 1; j < embeddings.size(); ++j) {
            total_sim += cosine_similarity(embeddings[i], embeddings[j]);
            pairs++;
        }
    }

    double avg_sim = pairs > 0 ? total_sim / pairs : 0;

    // Output JSON
    // Should be written to /home/user/output/experiment_log.json
    cout << "Avg sim: " << avg_sim << endl;

    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
