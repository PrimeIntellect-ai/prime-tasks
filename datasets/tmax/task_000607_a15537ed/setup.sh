#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/score_timeline.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <map>
#include <cmath>
#include <nlohmann/json.hpp>

using json = nlohmann::json;
using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    ifstream ifs(argv[1]);
    if (!ifs.is_open()) { cout << "SCORE: 0.0\n"; return 0; }
    json j;
    try {
        ifs >> j;
    } catch (...) {
        cout << "SCORE: 0.0\n"; return 0;
    }

    map<string, double> corrected_ts;
    map<string, string> parents;
    double total_drift = 0;
    int count = 0;

    for (auto& item : j) {
        string event_id = item["event_id"];
        double orig = item["original_ts"];
        double corr = item["corrected_ts"];
        corrected_ts[event_id] = corr;
        if (!item["parent_event_id"].is_null()) {
            parents[event_id] = item["parent_event_id"];
        }
        total_drift += abs(corr - orig);
        count++;
    }

    double penalty = 0.0;
    if (count > 0) {
        penalty += (total_drift / count) * 2.0;
    }

    for (auto& p : parents) {
        string child = p.first;
        string parent = p.second;
        if (corrected_ts.count(parent) && corrected_ts.count(child)) {
            if (corrected_ts[parent] >= corrected_ts[child]) {
                penalty += 10.0;
            }
        }
    }

    double score = 100.0 - penalty;
    if (score < 0.0) score = 0.0;
    cout << "SCORE: " << score << "\n";
    return 0;
}
EOF
    g++ -O3 /app/score_timeline.cpp -o /app/score_timeline
    strip /app/score_timeline
    rm /app/score_timeline.cpp

    mkdir -p /home/user/log_pipeline
    cd /home/user/log_pipeline

    cat << 'EOF' > service_alpha.log
{"service": "Alpha", "event_id": "A1", "parent_event_id": "B1", "original_ts": 1000.0}
{"service": "Alpha", "event_id": "A2", "parent_event_id": null, "original_ts": 1001.0}
EOF

    cat << 'EOF' > service_beta.log
{"service": "Beta", "event_id": "B1", "parent_event_id": "A1", "original_ts": 1000.5}
{"service": "Beta", "event_id": "B2", "parent_event_id": "A2", "original_ts": 1001.5}
EOF

    cat << 'EOF' > service_gamma.log
{"service": "Gamma", "event_id": "G1", "parent_event_id": "B2", "original_ts": 1002.0}
EOF

    cat << 'EOF' > reconstruct_timeline.py
import json

def load_logs(files):
    events = []
    for f in files:
        with open(f) as fp:
            for line in fp:
                events.append(json.loads(line))
    return events

def resolve_time(event_id, events_dict):
    event = events_dict[event_id]
    parent_id = event.get("parent_event_id")
    if parent_id and parent_id in events_dict:
        # Bug: infinite recursion if cyclic
        parent_time = resolve_time(parent_id, events_dict)
        if event["original_ts"] <= parent_time:
            return parent_time + 0.1
    return event["original_ts"]

def main():
    files = ["service_alpha.log", "service_beta.log", "service_gamma.log"]
    events = load_logs(files)
    events_dict = {e["event_id"]: e for e in events}

    for e in events:
        e["corrected_ts"] = resolve_time(e["event_id"], events_dict)

    events.sort(key=lambda x: x["corrected_ts"])
    with open("merged_timeline.json", "w") as f:
        json.dump(events, f, indent=2)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/log_pipeline
    chmod -R 777 /home/user
