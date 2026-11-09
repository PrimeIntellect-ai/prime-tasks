#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask fastapi uvicorn requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy
    mkdir -p /home/user/green

    cat << 'EOF' > /home/user/legacy/cache.cpp
#include <iostream>
#include <string>
#include <unordered_map>
#include <list>
#include <map>

// Reference Implementation of PriorityLifoCache
class PriorityLifoCache {
    struct Node {
        std::string key;
        std::string value;
        int priority;
    };

    std::unordered_map<std::string, std::list<Node>::iterator> keyMap;
    // Map priority to a list of Nodes (LIFO: push front, remove front)
    std::map<int, std::list<Node>> priorityMap;

public:
    void put(const std::string& key, const std::string& value, int priority) {
        if (keyMap.find(key) != keyMap.end()) {
            auto it = keyMap[key];
            priorityMap[it->priority].erase(it);
            if (priorityMap[it->priority].empty()) {
                priorityMap.erase(it->priority);
            }
        }
        priorityMap[priority].push_front({key, value, priority});
        keyMap[key] = priorityMap[priority].begin();
    }

    Node evict() {
        if (priorityMap.empty()) throw std::runtime_error("Empty");
        auto minIt = priorityMap.begin();
        Node evicted = minIt->second.front();
        minIt->second.pop_front();
        if (minIt->second.empty()) {
            priorityMap.erase(minIt);
        }
        keyMap.erase(evicted.key);
        return evicted;
    }

    std::string get(const std::string& key) {
        if (keyMap.find(key) == keyMap.end()) return "";
        return keyMap[key]->value;
    }
};
EOF

    chmod -R 777 /home/user
