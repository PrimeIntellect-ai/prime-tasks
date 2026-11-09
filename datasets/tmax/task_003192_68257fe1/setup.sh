#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/MathRouter/src
    mkdir -p /home/user/MathRouter/tests

    cat << 'EOF' > /home/user/MathRouter/src/router.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <cmath>
#include <numeric>

std::vector<double> parse_params(const std::string& query) {
    std::vector<double> result;
    size_t pos = query.find("vals=");
    if (pos == std::string::npos) return result;

    std::string vals_str = query.substr(pos + 5);
    size_t space_pos = vals_str.find(" ");
    if (space_pos != std::string::npos) {
        vals_str = vals_str.substr(0, space_pos);
    }

    std::stringstream ss(vals_str);
    std::string item;
    while (std::getline(ss, item, ',')) {
        // BUG: parses as int instead of double
        result.push_back(std::stoi(item));
    }
    return result;
}

std::string handle_request(const std::string& request) {
    if (request.find("GET /api/geom_mean") == 0) {
        std::vector<double> vals = parse_params(request);
        if (vals.empty()) return R"({"error": "no values"})";

        // BUG: Ownership / use-after-move bug
        std::vector<double> moved_vals = std::move(vals);

        double product = 1.0;
        for (double v : vals) { // Error: iterating over moved-from vector
            product *= v;
        }

        double geom_mean = std::pow(product, 1.0 / moved_vals.size());

        return R"({"result": )" + std::to_string(geom_mean) + "}";
    }
    return R"({"error": "not found"})";
}
EOF

    cat << 'EOF' > /home/user/MathRouter/tests/test_router.cpp
#include <iostream>
#include <string>
#include <cmath>

std::string handle_request(const std::string& request);

class MockServerFixture {
public:
    bool initialized = false;

    void setup() {
        // Supposed to initialize server
    }

    std::string simulate_request(const std::string& req) {
        if (!initialized) return R"({"error": "uninitialized"})";
        return handle_request(req);
    }
};

int main() {
    MockServerFixture fixture;
    // BUG: Missing fixture.initialized = true; or fixture setup

    std::string req = "GET /api/geom_mean?vals=2.0,8.0 HTTP/1.1";
    std::string res = fixture.simulate_request(req);

    // BUG: wrong expected output format
    std::string expected = R"({"answer": 4.000000})";

    if (res != expected) {
        std::cerr << "Test failed! Expected: " << expected << ", Got: " << res << std::endl;
        return 1;
    }

    std::cout << "CI SUCCESS: All tests passed." << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/MathRouter/ci.sh
#!/bin/bash

# Simple static analysis to catch the use-after-move
if grep -q "for.*:.*vals" src/router.cpp && grep -q "std::move(vals)" src/router.cpp; then
    echo "Linter Error: Use-after-move detected on 'vals'."
    exit 1
fi

g++ -std=c++17 src/router.cpp tests/test_router.cpp -o test_runner
if [ $? -ne 0 ]; then
    echo "Compilation failed."
    exit 1
fi

./test_runner
EOF

    chmod +x /home/user/MathRouter/ci.sh
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
