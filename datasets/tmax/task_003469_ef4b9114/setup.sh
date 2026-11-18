#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip clang g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uptime_monitor

    cat << 'EOF' > /home/user/uptime_monitor/parser.h
#pragma once
#include <string>

struct LogEntry {
    int year, month, day;
    std::string service_name;
    int status_code;
};

LogEntry ParseLogLine(const std::string& line);
EOF

    cat << 'EOF' > /home/user/uptime_monitor/parser.cpp
#include "parser.h"
#include <vector>
#include <sstream>
#include <stdexcept>
#include <iostream>

bool IsLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
}

LogEntry ParseLogLine(const std::string& line) {
    // Format: [YYYY-MM-DD] SERVICE_NAME STATUS_CODE
    if (line.length() < 15 || line[0] != '[' || line[11] != ']') {
        throw std::invalid_argument("Invalid format");
    }

    LogEntry entry;
    entry.year = std::stoi(line.substr(1, 4));
    entry.month = std::stoi(line.substr(6, 2));
    entry.day = std::stoi(line.substr(9, 2));

    int days_in_month[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

    // BUG 1: Off-by-one error. month is 1-12, array is 0-11. 
    // If month is 12, it reads out of bounds. Also leap year check uses buggy index.
    if (entry.month < 1 || entry.month > 12) throw std::invalid_argument("Invalid month");

    int max_days = days_in_month[entry.month]; // BUGGY
    if (entry.month == 2 && IsLeapYear(entry.year)) {
        max_days = 29;
    }

    if (entry.day < 1 || entry.day > max_days) {
        throw std::invalid_argument("Invalid day");
    }

    std::string remainder = line.substr(13);
    std::vector<std::string> parts;
    std::stringstream ss(remainder);
    std::string token;
    while (std::getline(ss, token, ' ')) {
        if (!token.empty()) parts.push_back(token);
    }

    if (parts.size() < 2) throw std::invalid_argument("Missing parts");

    // BUG 2: Assumes parts[0] is service, parts[1] is status.
    // Fails if service name has spaces (e.g., "DATABASE SERVER 200")
    entry.service_name = parts[0];
    entry.status_code = std::stoi(parts[1]); // Crashes if parts[1] is a string like "SERVER"

    return entry;
}
EOF

    cat << 'EOF' > /home/user/uptime_monitor/main.cpp
#include "parser.h"
#include <iostream>
#include <fstream>
#include <map>

int main() {
    std::ifstream infile("production.log");
    std::string line;
    std::map<std::string, std::map<int, int>> stats;

    while (std::getline(infile, line)) {
        if (line.empty()) continue;
        try {
            LogEntry entry = ParseLogLine(line);
            stats[entry.service_name][entry.status_code]++;
        } catch (const std::exception& e) {
            // Ignore invalid lines in production
        }
    }

    std::cout << "{\n";
    bool first_svc = true;
    for (const auto& svc : stats) {
        if (!first_svc) std::cout << ",\n";
        first_svc = false;
        std::cout << "  \"" << svc.first << "\": {\n";
        bool first_stat = true;
        for (const auto& stat : svc.second) {
            if (!first_stat) std::cout << ",\n";
            first_stat = false;
            std::cout << "    \"" << stat.first << "\": " << stat.second;
        }
        std::cout << "\n  }";
    }
    std::cout << "\n}\n";
    return 0;
}
EOF

    cat << 'EOF' > /home/user/uptime_monitor/production.log
[2023-12-15] API_GATEWAY 200
[2024-02-29] AUTH_SERVICE 500
[2023-12-31] DATABASE SERVER 200
[2023-11-30] API_GATEWAY 200
[2024-02-29] DATABASE SERVER 503
[2023-08-15] WEB APP 200
EOF

    chmod -R 777 /home/user
