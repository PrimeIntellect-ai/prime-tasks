#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ diffutils
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > api_server.py
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/data':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            # Corrupted data (1 character off per string, plus checksum)
            # Correct base: "1234", sum = (1*1 + 2*2 + 3*3 + 4*4)%10 = 30%10 = 0 -> "12340"
            # We corrupt the first string: "12840"
            # Correct base: "5678", sum = (5*1 + 6*2 + 7*3 + 8*4)%10 = 70%10 = 0 -> "56780"
            # Corrupted: "56781" (Wait, corruption in C code logic: if checksum doesn't match, it searches for single digit change to fix it)
            # Let's just use simple data
            data = {"payloads": ["19340", "56780", "99996", "00000"]}
            self.wfile.write(json.dumps(data).encode('utf-8'))

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), RequestHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// simple checksum: (d[0]*1 + d[1]*2 + d[2]*3 + d[3]*4) % 10 == d[4]
void decode_payload(const char* input, char* output) {
    char temp[6];
    strcpy(temp, input);
    int found = 0;

    for(int i=0; i<4 && !found; i++) {
        char orig = temp[i];
        for(int d='0'; d<='9'; d++) {
            temp[i] = d;
            int sum = ((temp[0]-'0')*1 + (temp[1]-'0')*2 + (temp[2]-'0')*3 + (temp[3]-'0')*4) % 10;
            if(sum == (temp[4]-'0')) {
                found = 1;
                break;
            }
        }
        if(!found) temp[i] = orig;
    }

    strncpy(output, temp, 4);
    output[4] = '\0';
}
EOF

    cat << 'EOF' > sorter.cpp
#include <iostream>
#include <vector>
#include <string>
#include <algorithm>

int main() {
    std::vector<int> nums;
    std::string line;
    while (std::cin >> line) {
        nums.push_back(std::stoi(line));
    }
    std::sort(nums.begin(), nums.end(), std::greater<int>());
    for (int n : nums) {
        // Output with leading zeros to match 4 chars
        char buf[10];
        snprintf(buf, sizeof(buf), "%04d", n);
        std::cout << buf << std::endl;
    }
    return 0;
}
EOF

    cat << 'EOF' > expected_output.txt
9999
5678
1234
0000
EOF

    chmod +x api_server.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
