#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make patch
    pip3 install pytest

    mkdir -p /home/user/math_release/src
    mkdir -p /home/user/math_release/patch
    mkdir -p /home/user/math_release/tests

    cat << 'EOF' > /home/user/math_release/src/evaluator.cpp
#include <iostream>
#include <string>
#include <stack>
#include <sstream>

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        std::stack<int> s;
        std::istringstream iss(line);
        std::string token;
        while (iss >> token) {
            if (token == "+" || token == "-" || token == "*") {
                int b = s.top(); s.pop();
                int a = s.top(); s.pop();
                if (token == "+") s.push(a + b);
                if (token == "-") s.push(b - a); // BUGGY LINE
                if (token == "*") s.push(a * b);
            } else {
                s.push(std::stoi(token));
            }
        }
        std::cout << s.top() << "\n";
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/math_release/patch/fix_subtraction.patch
--- src/evaluator.cpp
+++ src/evaluator.cpp
@@ -14,7 +14,7 @@
                 int b = s.top(); s.pop();
                 int a = s.top(); s.pop();
                 if (token == "+") s.push(a + b);
-                if (token == "-") s.push(b - a); // BUGGY LINE
+                if (token == "-") s.push(a - b);
                 if (token == "*") s.push(a * b);
             } else {
                 s.push(std::stoi(token));
EOF

    cat << 'EOF' > /home/user/math_release/tests/inputs.txt
5 3 +
10 4 -
2 3 * 4 +
20 5 - 3 *
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
