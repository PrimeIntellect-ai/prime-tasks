#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git g++ cmake make binutils
pip3 install pytest

mkdir -p /app
cd /app
git clone --branch 2023-11-01 https://github.com/google/re2.git re2-src

# Replace the C++ standard flags with c++98 to introduce the perturbation
sed -i -E 's/-std=c\+\+[0-9]+/-std=c++98/g' /app/re2-src/Makefile
sed -i -E 's/CXX_STANDARD [0-9]+/CXX_STANDARD 98/g' /app/re2-src/CMakeLists.txt

# Fallback in case regex missed (e.g., if flags were different)
if ! grep -q "\-std=c++98" /app/re2-src/Makefile; then
    sed -i 's/CXXFLAGS?=/CXXFLAGS?=-std=c++98 /g' /app/re2-src/Makefile
fi
if ! grep -q "CXX_STANDARD 98" /app/re2-src/CMakeLists.txt; then
    # Add it near the top
    sed -i '1s/^/set(CMAKE_CXX_STANDARD 98)\n/' /app/re2-src/CMakeLists.txt
fi

# Create the legacy filter binary
cat << 'EOF' > /app/legacy_filter.cpp
#include <iostream>
#include <string>
int main() {
    std::string sqli_sig = "(?i)(UNION.*SELECT|SELECT.*FROM|DROP.*TABLE)";
    std::string xss_sig = "(?i)(<script.*?>|javascript:|onerror=)";
    std::cout << "Filter initialized." << std::endl;
    return 0;
}
EOF
g++ -O2 /app/legacy_filter.cpp -o /app/legacy_filter
strip /app/legacy_filter
rm /app/legacy_filter.cpp

# Create the corpora
mkdir -p /app/corpus/clean /app/corpus/evil
echo "user: admin, key: ssh-rsa AAAAB3Nza..." > /app/corpus/clean/clean1.txt
echo "user: dev_user, key: ecdsa-sha2-nistp256 AAAAE2..." > /app/corpus/clean/clean2.txt
echo "user: admin' UNION SELECT null, null--, key: ssh-rsa ..." > /app/corpus/evil/evil1.txt
echo "user: test, key: ssh-rsa <script>alert(1)</script>" > /app/corpus/evil/evil2.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
