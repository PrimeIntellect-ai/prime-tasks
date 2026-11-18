#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    apt-get install -y g++ valgrind

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/build.old
Target: all
Depends: frontend,backend
Command: echo "Building all"

Target: frontend
Depends: ui_components
Command: sleep 1 && echo "Frontend built"

Target: backend
Depends: database
Command: sleep 2 && echo "Backend built"

Target: ui_components
Depends: 
Command: echo "UI built"

Target: database
Depends: 
Command: echo "DB built"
EOF

    cat << 'EOF' > /home/user/project/minibuild.cpp
#include <iostream>
#include <vector>
#include <string>
#include <unordered_map>
#include <fstream>
#include <sstream>
#include <chrono>
#include <cstdlib>

struct Target {
    std::string name;
    std::vector<std::string> deps;
    std::string cmd;
    bool visited = false;
    bool built = false;
};

std::unordered_map<std::string, Target*> targets;

void parse(const std::string& file) {
    std::ifstream in(file);
    std::string line;
    Target* curr = nullptr;
    while (std::getline(in, line)) {
        if (line.empty()) continue;
        if (line.rfind("TARGET ", 0) == 0) {
            curr = new Target();
            curr->name = line.substr(7);
            targets[curr->name] = curr;
        } else if (line.rfind("DEPS", 0) == 0 && curr) {
            if (line.length() > 5) {
                std::stringstream ss(line.substr(5));
                std::string dep;
                while (ss >> dep) curr->deps.push_back(dep);
            }
        } else if (line.rfind("CMD ", 0) == 0 && curr) {
            curr->cmd = line.substr(4);
        }
    }
}

void build(Target* t, std::ofstream& log) {
    if (t->built) return;
    if (t->visited) { std::cerr << "Cycle!\n"; exit(1); }
    t->visited = true;

    for (const auto& dep : t->deps) {
        if (targets.find(dep) == targets.end()) {
            std::cerr << "Missing dep: " << dep << "\n";
            exit(1);
        }
        build(targets[dep], log);
    }

    auto start = std::chrono::steady_clock::now();
    int ret = std::system(t->cmd.c_str());
    if (ret != 0) {
        std::cerr << "Command failed\n";
        exit(1);
    }
    auto end = std::chrono::steady_clock::now();
    auto diff = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    log << t->name << " " << diff << "ms\n";
    t->built = true;

    // INTENTIONAL BUG: use-after-free and multiple frees will happen because multiple targets
    // might depend on the same target, or it's accessed in main loop later.
    delete t;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <build_file>\n";
        return 1;
    }
    parse(argv[1]);
    std::ofstream log("/home/user/project/benchmark.log");
    for (auto& pair : targets) {
        build(pair.second, log);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
