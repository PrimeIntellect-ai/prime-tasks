#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate.go
package main

import (
	"fmt"
	"os"
	"sync"
)

func main() {
	f, err := os.Create("/home/user/data.bin")
	if err != nil {
		panic(err)
	}
	defer f.Close()

	ch := make(chan []byte, 100)
	var wg sync.WaitGroup
    var consumerWg sync.WaitGroup

    consumerWg.Add(1)
	go func() {
        defer consumerWg.Done()
		for b := range ch {
			f.Write(b)
		}
	}()

	for i := 0; i < 50; i++ {
        // BUG: missing wg.Add(1)
		go func(id int) {
            // BUG: missing defer wg.Done()
			msg := fmt.Sprintf("Event-%d", id)
			buf := make([]byte, 1+len(msg))
			buf[0] = byte(len(msg))
			copy(buf[1:], msg)
			ch <- buf
		}(i)
	}

    // BUG: missing wg.Wait()
    // BUG: missing close(ch)
    // BUG: missing consumerWg.Wait()
}
EOF

    cat << 'EOF' > /home/user/parser.cpp
#include <iostream>
#include <fstream>
#include <string>

class EventBuffer {
    std::ifstream file;
public:
    EventBuffer(const std::string& path) : file(path, std::ios::binary) {}

    bool readNext(std::string& outStr) {
        char lenByte;
        if (!file.read(&lenByte, 1)) {
            return false;
        }
        int len = static_cast<unsigned char>(lenByte);

        // BUG 1: Buffer is exactly 'len' size, but we write to buf[len] below
        char* buf = new char[len]; 
        file.read(buf, len);

        // BUG 2: Out of bounds write
        buf[len] = '\0'; 

        outStr = std::string(buf);

        // BUG 3: Mismatched array new/delete (Undefined behavior)
        delete buf; 
        return true;
    }
};

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    EventBuffer reader(argv[1]);
    std::string event;
    while (reader.readNext(event)) {
        std::cout << "Parsed: " << event << std::endl;
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
