#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk coreutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_recommender.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <map>
#include <set>
#include <sstream>
#include <algorithm>

using namespace std;

struct Item {
    long long f1;
    long long f2;
};

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;

    map<long long, Item> items;
    ifstream f_items(argv[2]);
    string line;
    while (getline(f_items, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string token;
        long long iid, f1, f2;
        getline(ss, token, ','); iid = stoll(token);
        getline(ss, token, ','); f1 = stoll(token);
        getline(ss, token, ','); f2 = stoll(token);
        items[iid] = {f1, f2};
    }

    map<long long, pair<long long, long long>> user_profiles;
    map<long long, set<long long>> user_rated;

    ifstream f_ratings(argv[1]);
    while (getline(f_ratings, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string token;
        long long uid, iid, rating;
        getline(ss, token, ','); uid = stoll(token);
        getline(ss, token, ','); iid = stoll(token);
        getline(ss, token, ','); rating = stoll(token);

        user_rated[uid].insert(iid);
        if (items.count(iid)) {
            user_profiles[uid].first += items[iid].f1 * rating;
            user_profiles[uid].second += items[iid].f2 * rating;
        }
    }

    for (auto const& [uid, profile] : user_profiles) {
        long long best_item = -1;
        long long best_score = -1;
        long long uf1 = profile.first;
        long long uf2 = profile.second;

        for (auto const& [iid, item] : items) {
            if (user_rated[uid].count(iid)) continue;
            long long score = uf1 * item.f1 + uf2 * item.f2;
            if (score > best_score) {
                best_score = score;
                best_item = iid;
            } else if (score == best_score) {
                if (best_item == -1 || iid < best_item) {
                    best_item = iid;
                }
            }
        }
        if (best_item != -1) {
            cout << uid << "," << best_item << "\n";
        }
    }
    return 0;
}
EOF

    g++ -O3 -o /app/legacy_recommender /app/legacy_recommender.cpp
    strip /app/legacy_recommender
    rm /app/legacy_recommender.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
