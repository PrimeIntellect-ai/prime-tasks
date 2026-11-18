#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make patch binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_encoder.cpp
#include <iostream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cout << std::endl;
        return 0;
    }
    std::string s = argv[1];
    if (s.empty()) {
        std::cout << std::endl;
        return 0;
    }
    std::string out = "";
    int count = 1;
    for (size_t i = 1; i < s.length(); ++i) {
        if (s[i] == s[i-1]) {
            count++;
        } else {
            out += s[i-1] + std::to_string(count);
            count = 1;
        }
    }
    out += s.back() + std::to_string(count);
    std::cout << out << std::endl;
    return 0;
}
EOF
    g++ -O2 /app/legacy_encoder.cpp -o /app/legacy_encoder
    strip /app/legacy_encoder
    rm /app/legacy_encoder.cpp

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/main.cpp
#include <iostream>
#include "encoder.h"

int main(int argc, char* argv[]) {
    if (argc < 2) return 0;
    std::cout << encode_string(argv[1]) << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/encoder.h
#include "utils.h"
#include <string>
std::string encode_string(const std::string& input);
struct EncoderData {
    UtilsData u;
};
EOF

    cat << 'EOF' > /home/user/project/utils.h
#include "encoder.h"
#include <string>
void print_utils();
struct UtilsData {
    EncoderData* e;
};
EOF

    cat << 'EOF' > /home/user/project/encoder.cpp
#include "encoder.h"
std::string encode_string(const std::string& input) {
    return "";
}
EOF

    cat << 'EOF' > /home/user/project/utils.cpp
#include "utils.h"
#include <iostream>
void print_utils() {
    std::cout << "Utils" << std::endl;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
CXX=g++
CXXFLAGS=-Wall -Wextra -std=c++11

rle_encoder: main.o encoder.o
    $(CXX) $(CXXFLAGS) -o rle_encoder main.o encoder.o

main.o: main.cpp
    $(CXX) $(CXXFLAGS) -c main.cpp

encoder.o: encoder.cpp
    $(CXX) $(CXXFLAGS) -c encoder.cpp

utils.o: utils.cpp
    $(CXX) $(CXXFLAGS) -c utils.cpp

clean:
    rm -f *.o rle_encoder
EOF

    cat << 'EOF' > /home/user/benchmarking.patch
--- project/main.cpp
+++ project/main.cpp
@@ -1,8 +1,13 @@
 #include <iostream>
 #include "encoder.h"
+#include <chrono>

 int main(int argc, char* argv[]) {
     if (argc < 2) return 0;
+    auto start = std::chrono::high_resolution_clock::now();
     std::cout << encode_string(argv[1]) << std::endl;
+    auto end = std::chrono::high_resolution_clock::now();
+    std::chrono::duration<double> diff = end - start;
+    std::cerr << "Time: " << diff.count() << " s\n";
     return 0;
 }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
