#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    mkdir -p /home/user/data
    mkdir -p /home/user/tracker

    cat << 'EOF' > /home/user/data/models.csv
model_id,prior_alpha,prior_beta
m1,2.0,2.0
m2,5.0,2.0
EOF

    cat << 'EOF' > /home/user/data/trials.csv
model_id,successes,failures,embedding
m1,10,2,0.1;0.5;0.8
m2,15,5,0.8;0.2;0.1
EOF

    cat << 'EOF' > /home/user/data/query.txt
0.2;0.4;0.7
EOF

    cat << 'EOF' > /home/user/tracker/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -O2

artifact_tracker: artifact_tracker.cpp
	$(CXX) $(CXXFLAGS) -o artifact_tracker artifact_tracker.cpp
EOF

    cat << 'EOF' > /home/user/tracker/artifact_tracker.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <map>
#include <vector>
#include <cmath>
#include <iomanip>
#include <boost/math/distributions/beta.hpp>

using namespace std;

struct ModelData {
    double prior_alpha;
    double prior_beta;
    int successes;
    int failures;
    vector<double> embedding;
};

vector<double> parse_embedding(const string& s) {
    vector<double> emb;
    stringstream ss(s);
    string item;
    while (getline(ss, item, ';')) {
        emb.push_back(stod(item));
    }
    return emb;
}

double cosine_similarity(const vector<double>& v1, const vector<double>& v2) {
    double dot = 0.0, denom_a = 0.0, denom_b = 0.0;
    for(size_t i = 0; i < v1.size(); ++i) {
        dot += v1[i] * v2[i];
        denom_a += v1[i] * v1[i];
        denom_b += v2[i] * v2[i];
    }
    return dot / (sqrt(denom_a) * sqrt(denom_b));
}

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;

    ifstream qf(argv[1]);
    string qline;
    getline(qf, qline);
    vector<double> query = parse_embedding(qline);

    map<string, ModelData> models;

    ifstream mf("/home/user/data/models.csv");
    string line;
    getline(mf, line); // header
    while (getline(mf, line)) {
        stringstream ss(line);
        string id, a, b;
        getline(ss, id, ',');
        getline(ss, a, ',');
        getline(ss, b, ',');
        models[id].prior_alpha = stod(a);
        models[id].prior_beta = stod(b);
    }

    ifstream tf("/home/user/data/trials.csv");
    getline(tf, line); // header
    while (getline(tf, line)) {
        stringstream ss(line);
        string id, s, f, emb_str;
        getline(ss, id, ',');
        getline(ss, s, ',');
        getline(ss, f, ',');
        getline(ss, emb_str, ',');
        models[id].successes = stoi(s);
        models[id].failures = stoi(f);
        models[id].embedding = parse_embedding(emb_str);
    }

    ofstream out("output.csv");
    out << "model_id,post_alpha,post_beta,map_estimate,similarity,final_score\n";

    for (const auto& pair : models) {
        double p_alpha = pair.second.prior_alpha + pair.second.successes;
        double p_beta = pair.second.prior_beta + pair.second.failures;

        // THE BUG: integer division
        double map_est = (int(p_alpha) - 1) / (int(p_alpha) + int(p_beta) - 2);

        double sim = cosine_similarity(pair.second.embedding, query);
        double final_score = map_est * sim;

        out << pair.first << "," 
            << fixed << setprecision(4) << p_alpha << "," 
            << p_beta << "," 
            << map_est << "," 
            << sim << "," 
            << final_score << "\n";
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
