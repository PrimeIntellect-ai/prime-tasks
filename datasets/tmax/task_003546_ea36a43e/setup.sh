#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake wget nlohmann-json3-dev
    pip3 install pytest requests

    # Create oracle solver
    mkdir -p /app
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <cmath>
#include <iomanip>
#include <cstdlib>

using namespace std;

double f(double a, double b, double c, double d, double x) {
    return a*x*x*x + b*x*x + c*x + d;
}

double df(double a, double b, double c, double x) {
    return 3*a*x*x + 2*b*x + c;
}

int main(int argc, char* argv[]) {
    if (argc != 5) return 1;
    double a = atof(argv[1]);
    double b = atof(argv[2]);
    double c = atof(argv[3]);
    double d = atof(argv[4]);

    double x = 0.0;
    for (int i = 0; i < 1000; i++) {
        double fx = f(a, b, c, d, x);
        if (abs(fx) < 1e-9) break;
        double dfx = df(a, b, c, x);
        if (abs(dfx) < 1e-12) {
            x += 0.1; // perturb
            continue;
        }
        x = x - fx / dfx;
    }
    cout << fixed << setprecision(6) << x << endl;
    return 0;
}
EOF
    g++ -O3 /app/oracle.cpp -o /app/oracle_solver
    strip -s /app/oracle_solver
    rm /app/oracle.cpp

    # Create workspace
    mkdir -p /workspace/math_server

    # Download httplib.h
    wget -qO /workspace/math_server/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    cat << 'EOF' > /workspace/math_server/solver.h
#ifndef SOLVER_H
#define SOLVER_H

float solve_cubic(float a, float b, float c, float d);

#endif
EOF

    cat << 'EOF' > /workspace/math_server/solver.cpp
#include "solver.h"
#include <cmath>

float solve_cubic(float a, float b, float c, float d) {
    float x = 0.0f;
    // Bug: no iteration limit, float precision issue
    while (std::abs(a*x*x*x + b*x*x + c*x + d) > 1e-7f) {
        float fx = a*x*x*x + b*x*x + c*x + d;
        float dfx = 3*a*x*x + 2*b*x + c;
        x = x - fx / dfx;
    }
    return x;
}
EOF

    cat << 'EOF' > /workspace/math_server/main.cpp
#include "httplib.h"
#include <nlohmann/json.hpp>
#include "solver.h"
#include <iostream>

using json = nlohmann::json;

int main() {
    httplib::Server svr;

    svr.Post("/solve", [](const httplib::Request& req, httplib::Response& res) {
        try {
            auto j = json::parse(req.body);
            float a = j["a"];
            float b = j["b"];
            float c = j["c"];
            float d = j["d"];

            float root = solve_cubic(a, b, c, d);

            json res_j;
            res_j["root"] = root;
            res.set_content(res_j.dump(), "application/json");
        } catch (...) {
            res.status = 400;
            res.set_content("Bad Request", "text/plain");
        }
    });

    std::cout << "Starting server on 127.0.0.1:8080\n";
    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

    cat << 'EOF' > /workspace/math_server/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(math_server)

set(CMAKE_CXX_STANDARD 17)

find_package(nlohmann_json REQUIRED)

# Bug: missing find_package(Threads) and linking against Threads::Threads
# This causes cpp-httplib to fail to build/link

add_executable(math_server main.cpp solver.cpp)
target_link_libraries(math_server nlohmann_json::nlohmann_json)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /workspace
