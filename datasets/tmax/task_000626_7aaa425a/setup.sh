#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app/vendored/tiny-json-lines

    cat << 'EOF' > /app/vendored/tiny-json-lines/Makefile
CXXFLAGS = -O2 -std=c++11

all: libtinyjson.a

libtinyjson.a: parser.o
	ar rcs $@ $^

parser.o: parser.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<
EOF

    cat << 'EOF' > /app/vendored/tiny-json-lines/parser.cpp
#include <string>

std::string parse_string(const std::string& input) {
    std::string result;
    for (size_t i = 0; i < input.length(); ++i) {
        if (input[i] == '\\' && i + 1 < input.length() && input[i+1] == 'u') {
            // BUG: skips 5 characters without converting
            i += 5;
        } else {
            result += input[i];
        }
    }
    return result;
}
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/mask_loc_oracle
#!/bin/bash
# Dummy oracle binary
EOF
    chmod +x /opt/oracle/mask_loc_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
