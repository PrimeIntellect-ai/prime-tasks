#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk nginx coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/url_tool.cpp
#include <iostream>
#include <string>
#include <vector>
#include <cstdlib>
#include <ctime>

std::string encode_url(const std::string& value) {
    std::string escaped = "";
    escaped.reserve(value.length());
    for (char c : value) {
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            escaped += c;
        } else {
            char buf[5];
            snprintf(buf, 5, "%%%02X", (unsigned char)c);
            escaped.append(buf);
        }
    }
    return escaped;
}

std::string decode_url(const std::string& src) {
    std::string ret;
    char ch;
    int i, ii;
    for (i = 0; i < src.length(); i++) {
        if (src[i] == '%') {
            if(src[i+1]>='a') { ii = 0; } else { sscanf(src.substr(i + 1, 2).c_str(), "%x", &ii); }
            ch = static_cast<char>(ii);
            // BUG: Intentionally flawed fallback for certain ranges, user needs to fix
            // Wait, standard sscanf works. Let's introduce a manual bug.
            ret += ch;
            i = i + 2;
        } else if (src[i] == '+') {
            ret += ' ';
        } else {
            ret += src[i];
        }
    }
    return ret;
}

void run_property_tests() {
    // TODO: implement property based test
    // generate 1000 random strings
    // encode, decode, check
}

int main(int argc, char** argv) {
    if (argc > 1 && std::string(argv[1]) == "--test") {
        run_property_tests();
        return 0;
    }
    std::string line;
    while (std::getline(std::cin, line)) {
        std::cout << decode_url(line) << std::endl;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/access.log
192.168.1.1 - - [10/Oct/2000:13:55:36 -0700] "GET /vulnerable%20path HTTP/1.0" 200 2326
192.168.1.2 - - [10/Oct/2000:13:55:37 -0700] "GET /safe/path HTTP/1.0" 200 2326
192.168.1.3 - - [10/Oct/2000:13:55:38 -0700] "GET /admin%2fconfig%3fa%3db HTTP/1.0" 200 2326
192.168.1.4 - - [10/Oct/2000:13:55:39 -0700] "GET /etc/passwd HTTP/1.0" 200 2326
EOF

    cat << 'EOF' > /home/user/known_bad.txt
/admin/config?a=b
/etc/passwd
/vulnerable path
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
