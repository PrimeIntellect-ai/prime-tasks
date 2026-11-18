#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget git
    pip3 install pytest requests

    # Clone nlohmann_json
    mkdir -p /app
    git clone --branch v3.11.2 --depth 1 https://github.com/nlohmann/json.git /app/nlohmann_json

    # Perturb json.hpp to hardcode precision to 2
    sed -i 's/std::numeric_limits<number_float_t>::max_digits10/2/g' /app/nlohmann_json/single_include/nlohmann/json.hpp

    # Setup app directory
    mkdir -p /home/user/app

    # Download cpp-httplib
    wget -O /home/user/app/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    # Create server.cpp
    cat << 'EOF' > /home/user/app/server.cpp
#include "httplib.h"
#include <nlohmann/json.hpp>
#include <vector>

using json = nlohmann::json;

int main() {
    httplib::Server svr;

    svr.Post("/variance", [](const httplib::Request &req, httplib::Response &res) {
        try {
            auto j = json::parse(req.body);
            std::vector<double> data = j["data"];
            if (data.size() < 2) {
                res.status = 400;
                return;
            }
            double sum = 0.0;
            double sum_sq = 0.0;
            for (double x : data) {
                sum += x;
                sum_sq += x * x;
            }
            double mean = sum / data.size();
            double variance = (sum_sq - data.size() * mean * mean) / (data.size() - 1);

            json response;
            response["variance"] = variance;
            res.set_content(response.dump(), "application/json");
        } catch (...) {
            res.status = 400;
        }
    });

    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > /home/user/app/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -I/app/nlohmann_json/single_include -O2

server: server.cpp
	$(CXX) $(CXXFLAGS) -o server server.cpp -lpthread

clean:
	rm -f server
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod -R 777 /home/user
