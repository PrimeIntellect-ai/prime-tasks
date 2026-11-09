#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/stack-vm
    cd /home/user/stack-vm

    cat << 'EOF' > vm_engine.h
#pragma once
#include <vector>
#include <string>

class VMEngine {
    std::vector<int> stack;
public:
    void push(int val);
    void add();
    void sub();
    bool save_state(const std::string& filepath);
    bool load_state(const std::string& filepath);
    void print_top(const std::string& filepath);
};
EOF

    cat << 'EOF' > vm_engine.cpp
#include "vm_engine.h"
#include <fstream>

void VMEngine::push(int val) { stack.push_back(val); }
void VMEngine::add() {
    if(stack.size()<2) return;
    int a = stack.back(); stack.pop_back();
    int b = stack.back(); stack.pop_back();
    stack.push_back(a+b);
}
void VMEngine::sub() {
    if(stack.size()<2) return;
    int a = stack.back(); stack.pop_back();
    int b = stack.back(); stack.pop_back();
    stack.push_back(b-a);
}
bool VMEngine::save_state(const std::string& filepath) {
    // TODO: Implement serialization
    return false;
}
bool VMEngine::load_state(const std::string& filepath) {
    // TODO: Implement deserialization
    return false;
}
void VMEngine::print_top(const std::string& filepath) {
    if(stack.empty()) return;
    std::ofstream out(filepath);
    out << stack.back() << "\n";
}
EOF

    cat << 'EOF' > main.cpp
#include "vm_engine.h"
#include <iostream>
#include <fstream>
#include <sstream>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <script.txt>\n";
        return 1;
    }
    VMEngine vm;
    std::ifstream in(argv[1]);
    std::string line;
    while(std::getline(in, line)) {
        std::istringstream iss(line);
        std::string cmd;
        iss >> cmd;
        if (cmd == "PUSH") {
            int val; iss >> val;
            vm.push(val);
        } else if (cmd == "ADD") {
            vm.add();
        } else if (cmd == "SUB") {
            vm.sub();
        } else if (cmd == "SAVE") {
            std::string path; iss >> path;
            vm.save_state(path);
        } else if (cmd == "LOAD") {
            std::string path; iss >> path;
            vm.load_state(path);
        } else if (cmd == "PRINT") {
            std::string path; iss >> path;
            vm.print_top(path);
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(StackVM)

# Intentionally broken: no include directories set, and executable isn't linked to the library
add_library(vm_engine SHARED vm_engine.cpp)
add_executable(vm-cli main.cpp)
EOF

    cat << 'EOF' > serialization.patch
--- vm_engine.cpp
+++ vm_engine.cpp
@@ -16,8 +16,19 @@
 }
 bool VMEngine::save_state(const std::string& filepath) {
-    // TODO: Implement serialization
-    return false;
+    std::ofstream out(filepath, std::ios::binary);
+    if(!out) return false;
+    size_t size = stack.size();
+    out.write(reinterpret_cast<const char*>(&size), sizeof(size));
+    if(size > 0) out.write(reinterpret_cast<const char*>(stack.data()), size * sizeof(int));
+    return true;
 }
 bool VMEngine::load_state(const std::string& filepath) {
-    // TODO: Implement deserialization
-    return false;
+    std::ifstream in(filepath, std::ios::binary);
+    if(!in) return false;
+    size_t size = 0;
+    in.read(reinterpret_cast<char*>(&size), sizeof(size));
+    stack.resize(size);
+    if(size > 0) in.read(reinterpret_cast<char*>(stack.data()), size * sizeof(int));
+    return true;
 }
EOF

    cat << 'EOF' > prog1.txt
PUSH 10
PUSH 20
ADD
SAVE /home/user/state.bin
EOF

    cat << 'EOF' > prog2.txt
LOAD /home/user/state.bin
PUSH 5
SUB
PRINT /home/user/result.log
EOF

    chown -R user:user /home/user/stack-vm
    chmod -R 777 /home/user
