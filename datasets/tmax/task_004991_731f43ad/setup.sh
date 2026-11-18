#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make redis-server sudo valgrind libcurl4-openssl-dev libhiredis-dev curl
    pip3 install pytest flask redis

    # Create workspace
    mkdir -p /home/user/workspace/src
    mkdir -p /home/user/workspace/corpus/clean
    mkdir -p /home/user/workspace/corpus/evil

    # start_services.sh
    cat << 'EOF' > /home/user/workspace/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /home/user/workspace/flask_api.py &
sleep 2
EOF
    chmod +x /home/user/workspace/start_services.sh

    # flask_api.py
    cat << 'EOF' > /home/user/workspace/flask_api.py
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/config')
def config():
    return jsonify({"allowed_crc32": [12345678, 87654321]})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Makefile
    cat << 'EOF' > /home/user/workspace/Makefile
CXX = g++
CXXFLAGS = -Wall -g -std=c++17

all: bin/telemetry_sanitizer

bin/telemetry_sanitizer: src/main.cpp src/decoder.cpp
	mkdir -p bin
	$(CXX) $(CXXFLAGS) -o $@ $^

clean:
	rm -rf bin
EOF

    # src/main.cpp
    cat << 'EOF' > /home/user/workspace/src/main.cpp
#include <iostream>
#include <string>

std::string decode_base64(const std::string& input);

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    std::cout << "Processing " << argv[1] << std::endl;
    return 0;
}
EOF

    # src/decoder.cpp
    cat << 'EOF' > /home/user/workspace/src/decoder.cpp
#include <string>

std::string decode_base64(const std::string& input) {
    char* buffer = new char[input.length()]; // BUG: memory leak, off-by-one
    for (size_t i = 0; i < input.length(); ++i) {
        buffer[i] = input[i];
    }
    return std::string(buffer, input.length());
}
EOF

    # Create dummy corpus files
    for i in {1..50}; do
        echo "clean_data_$i" | base64 > /home/user/workspace/corpus/clean/file_$i.txt
        echo "evil_data_$i" | base64 > /home/user/workspace/corpus/evil/file_$i.txt
    done

    # Create user
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # Permissions
    chmod -R 777 /home/user
