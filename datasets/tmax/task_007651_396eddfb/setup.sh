#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget curl jq
    pip3 install pytest

    mkdir -p /home/user/emulator_release /home/user/states

    wget -O /home/user/emulator_release/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h
    wget -O /home/user/emulator_release/json.hpp https://raw.githubusercontent.com/nlohmann/json/develop/single_include/nlohmann/json.hpp

    echo '{"stack": [10, 20], "pc": 0}' > /home/user/states/state_1.json
    echo '{"stack": [5], "pc": 1}' > /home/user/states/state_2.json

    cat << 'EOF' > /home/user/emulator_release/machine.h
#pragma once
#include <vector>
#include <memory>
#include <string>

class Instruction {
public:
    virtual ~Instruction() = default;
    virtual std::string execute(std::vector<int>& stack) = 0;
};

class Machine {
    std::vector<std::unique_ptr<Instruction>> instructions;
public:
    void add_instruction(std::unique_ptr<Instruction> inst);
    std::vector<std::unique_ptr<Instruction>> get_instructions(); // BAD DESIGN
    std::string run(std::vector<int>& stack, int pc);
};
EOF

    cat << 'EOF' > /home/user/emulator_release/machine.cpp
#include "machine.h"

void Machine::add_instruction(std::unique_ptr<Instruction> inst) {
    instructions.push_back(std::move(inst));
}

// BUG: Returning by value causes copy of unique_ptr
std::vector<std::unique_ptr<Instruction>> Machine::get_instructions() {
    return instructions;
}

std::string Machine::run(std::vector<int>& stack, int pc) {
    return "SUCCESS: Stack top is " + std::to_string(stack.back());
}
EOF

    cat << 'EOF' > /home/user/emulator_release/main.cpp
#include "httplib.h"
#include "json.hpp"
#include "machine.h"
#include <iostream>

using json = nlohmann::json;

int main() {
    httplib::Server svr;
    Machine machine;

    svr.Post("/load_and_run", [&](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body);
        if(j["version"] != 2) {
            res.set_content("Invalid Schema", "text/plain");
            return;
        }
        std::vector<int> stack = j["machine_state"]["data_stack"];
        int pc = j["machine_state"]["instruction_pointer"];

        std::string result = machine.run(stack, pc);
        res.set_content(result, "text/plain");
    });

    std::cout << "Starting server on 8080..." << std::endl;
    svr.listen("localhost", 8080);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/emulator_release/Makefile
emulator_server: main.cpp machine.cpp
	g++ -std=c++17 -pthread main.cpp machine.cpp -o emulator_server
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
