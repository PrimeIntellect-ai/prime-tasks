#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>

using namespace std;

struct Edge {
    int to;
    double weight;
    string type;
};

vector<string> split(const string& s, char delimiter) {
    vector<string> tokens;
    string token;
    istringstream tokenStream(s);
    while (getline(tokenStream, token, delimiter)) {
        tokens.push_back(token);
    }
    return tokens;
}

double dfs(int u, int target, int seq_idx, const vector<string>& sequence, const vector<vector<Edge>>& graph) {
    if (seq_idx == sequence.size()) {
        return (u == target) ? 1.0 : 0.0;
    }

    double total_score = 0.0;
    for (const auto& edge : graph[u]) {
        if (edge.type == sequence[seq_idx]) {
            double path_score = dfs(edge.to, target, seq_idx + 1, sequence, graph);
            if (path_score > 0) {
                total_score += edge.weight * path_score;
            }
        }
    }
    return total_score;
}

int main() {
    int N, M, Q;
    if (!(cin >> N >> M >> Q)) return 0;

    vector<vector<Edge>> graph(N);
    for (int i = 0; i < M; ++i) {
        int u, v;
        double w;
        string type;
        cin >> u >> v >> w >> type;
        graph[u].push_back({v, w, type});
    }

    for (int i = 0; i < Q; ++i) {
        int start, end;
        string seq_str;
        cin >> start >> end >> seq_str;
        vector<string> sequence = split(seq_str, ',');

        double result = dfs(start, end, 0, sequence, graph);
        cout << fixed << setprecision(4) << result << "\n";
    }

    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/legacy_matcher
    strip /app/legacy_matcher
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
