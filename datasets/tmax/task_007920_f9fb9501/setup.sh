#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/forensics/data

    cat << 'EOF' > /home/user/forensics/analyzer.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <vector>
#include <iomanip>

double calculate_risk(int base_score, int event_count, int time_window) {
    // BUG: Integer division
    return (base_score * 0.6) + ((event_count / time_window) * 0.4);
}

std::string clean_payload(std::string payload) {
    size_t pos = 0;
    while ((pos = payload.find("MAL_", pos)) != std::string::npos) {
        payload.replace(pos, 4, "CLEAN_");
        // BUG: if replacement happens, the next search might infinite loop or just the pointer isn't advanced correctly if we don't skip the newly inserted word
        // Actually, replacing "MAL_" with "CLEAN_" means the "MAL_" is gone, so it won't infinite loop on that.
        // Let's create an actual hang:
        // A custom token extractor that fails to advance if a malformed token is found.
    }

    pos = 0;
    // Real bug: stripping out bad bytes
    while ((pos = payload.find("0x00", pos)) != std::string::npos) {
        // Developer forgot to erase or advance!
        // BUG: Infinite loop here if "0x00" is present.
    }
    return payload;
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <input_csv> <output_csv>\n";
        return 1;
    }

    std::ifstream in(argv[1]);
    std::ofstream out(argv[2]);
    out << std::fixed << std::setprecision(2);

    std::string line;
    // skip header
    std::getline(in, line);
    out << "ID,RiskScore\n";

    while (std::getline(in, line)) {
        std::istringstream iss(line);
        std::string id, base_str, events_str, time_str, payload;

        std::getline(iss, id, ',');
        std::getline(iss, base_str, ',');
        std::getline(iss, events_str, ',');
        std::getline(iss, time_str, ',');
        std::getline(iss, payload, ',');

        if (id.empty()) continue;

        clean_payload(payload); // Hangs here if payload contains 0x00

        double score = calculate_risk(std::stoi(base_str), std::stoi(events_str), std::stoi(time_str));
        out << id << "," << score << "\n";
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/forensics/Makefile
all:
	g++ -O2 -Wall analyzer.cpp -o analyzer
EOF

    cat << 'EOF' > /home/user/forensics/data/batch_42.csv
ID,BaseScore,EventCount,TimeWindow,Payload
EVT-001,50,150,10,Normal_Payload
EVT-002,80,250,7,Suspicious_Activity
EVT-003,20,5,2,Routine_Check
EVT-004,90,300,8,Contains_0x00_Byte_Dropper
EVT-005,60,100,3,Lateral_Movement
EOF

    chown -R user:user /home/user/forensics
    chmod -R 777 /home/user
