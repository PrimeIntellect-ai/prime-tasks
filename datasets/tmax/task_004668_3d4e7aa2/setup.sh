#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas networkx

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    # Create the pattern matcher C++ source
    cat << 'EOF' > /app/pattern_matcher.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <map>

using namespace std;

struct QueryEdge { string u, rel, v; };

int main(int argc, char** argv) {
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " <graph.tsv> <query.txt>" << endl;
        return 1;
    }
    ifstream fg(argv[1]);
    unordered_map<string, vector<pair<string, string>>> graph;
    string u, r, v;
    while (fg >> u >> r >> v) {
        graph[r].push_back({u, v});
    }

    ifstream fq(argv[2]);
    vector<QueryEdge> q;
    while (fq >> u >> r >> v) {
        q.push_back({u, r, v});
    }

    int matches = 0;
    map<string, string> env;

    auto solve = [&](auto& self, int idx) -> void {
        if (idx == q.size()) {
            matches++;
            return;
        }
        string qu = q[idx].u;
        string qrel = q[idx].rel;
        string qv = q[idx].v;

        for (auto& edge : graph[qrel]) {
            string u_val = edge.first;
            string v_val = edge.second;

            bool ok = true;
            string old_u = "", old_v = "";

            if (qu[0] == '?') {
                if (env.count(qu) && env[qu] != u_val) ok = false;
                else if (!env.count(qu)) { env[qu] = u_val; old_u = qu; }
            } else if (qu != u_val) ok = false;

            if (ok) {
                if (qv[0] == '?') {
                    if (env.count(qv) && env[qv] != v_val) ok = false;
                    else if (!env.count(qv)) { env[qv] = v_val; old_v = qv; }
                } else if (qv != v_val) ok = false;
            }

            if (ok) {
                self(self, idx + 1);
            }

            if (old_u != "") env.erase(old_u);
            if (old_v != "") env.erase(old_v);
        }
    };

    solve(solve, 0);
    cout << "Matches: " << matches << endl;
    return 0;
}
EOF

    # Compile and strip the binary
    g++ -O2 -o /app/pattern_matcher /app/pattern_matcher.cpp
    strip /app/pattern_matcher
    rm /app/pattern_matcher.cpp

    # Generate the graph and query
    cat << 'EOF' > /tmp/generate_graph.py
import random

random.seed(42)
edges = []
# Create exactly 4521 matches
for i in range(4521):
    a = f"n{i}_1"
    b = f"n{i}_2"
    c = f"n{i}_3"
    d = f"n{i}_4"
    edges.append((a, "knows", b))
    edges.append((b, "follows", c))
    edges.append((c, "likes", d))

# Add noise edges up to 100,000
for i in range(100000 - len(edges)):
    a = f"noise_{random.randint(0, 50000)}"
    b = f"noise_{random.randint(0, 50000)}"
    edges.append((a, "noise_rel", b))

random.shuffle(edges)

with open('/home/user/raw_graph.tsv', 'w') as f:
    for e in edges:
        f.write(f"{e[0]}\t{e[1]}\t{e[2]}\n")
EOF
    python3 /tmp/generate_graph.py
    rm /tmp/generate_graph.py

    # Create the slow query
    cat << 'EOF' > /home/user/slow_query.txt
?a knows ?b
?b follows ?c
?c likes ?d
EOF

    chmod -R 777 /home/user
