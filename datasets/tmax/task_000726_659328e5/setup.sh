#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/messy_workspace

    cat << 'EOF' > /home/user/messy_workspace/string_history.hpp
#ifndef STRING_HISTORY_HPP
#define STRING_HISTORY_HPP

#include <string>
#include <vector>

class StringHistory {
    int capacity;
    std::vector<std::string> history;
public:
    StringHistory(int cap);
    void add(const std::string& str);
    const char* get(int index) const;
};

#endif
EOF

    cat << 'EOF' > /home/user/messy_workspace/string_history.cpp
#include "string_history.hpp"

StringHistory::StringHistory(int cap) : capacity(cap) {}

void StringHistory::add(const std::string& str) {
    history.insert(history.begin(), str);
    if (history.size() > capacity) {
        history.pop_back();
    }
}

const char* StringHistory::get(int index) const {
    if (index >= 0 && index < history.size()) {
        return history[index].c_str();
    }
    return nullptr;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
