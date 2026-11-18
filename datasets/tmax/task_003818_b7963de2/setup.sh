#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gdb
    pip3 install pytest

    mkdir -p /home/user/event_service/src

    cat << 'EOF' > /home/user/event_service/Makefile
CXX = g++
# INTENTIONAL BUG: Missing -std=c++17
CXXFLAGS = -Wall -O2

all: event_processor

event_processor: src/main.o src/processor.o
	$(CXX) $(CXXFLAGS) -o event_processor src/main.o src/processor.o

src/main.o: src/main.cpp
	$(CXX) $(CXXFLAGS) -c src/main.cpp -o src/main.o

src/processor.o: src/processor.cpp
	$(CXX) $(CXXFLAGS) -c src/processor.cpp -o src/processor.o

clean:
	rm -f src/*.o event_processor test_runner
EOF

    cat << 'EOF' > /home/user/event_service/src/processor.h
#ifndef PROCESSOR_H
#define PROCESSOR_H

class EventProcessor {
private:
    int buffer[10];
    int count;
public:
    EventProcessor();
    void add_event(int event_id, int value);
    int get_sum() const;
};

#endif
EOF

    cat << 'EOF' > /home/user/event_service/src/processor.cpp
#include "processor.h"
#include <iostream>
// INTENTIONAL BUG: Missing #include <numeric> for std::accumulate (causes build failure if used, but we'll use a manual loop to ensure compiler error is elsewhere or let them fix C++17)

EventProcessor::EventProcessor() : count(0) {
    for(int i=0; i<10; ++i) buffer[i] = 0;
}

void EventProcessor::add_event(int event_id, int value) {
    // INTENTIONAL BUG: Modulo operator on negative event_id yields negative index in C++.
    int index = event_id % 10; 
    buffer[index] = value; // Segfaults if index is negative
    count++;
}

int EventProcessor::get_sum() const {
    int sum = 0;
    for(int i=0; i<10; ++i) {
        sum += buffer[i];
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/event_service/src/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include "processor.h"

// INTENTIONAL BUG: uses std::string_view which requires C++17
void process_file(std::string_view filename, EventProcessor& proc) {
    std::ifstream file(std::string(filename));
    int id, val;
    while(file >> id >> val) {
        proc.add_event(id, val);
    }
}

int main(int argc, char** argv) {
    if(argc < 2) return 1;
    EventProcessor proc;
    process_file(argv[1], proc);
    std::cout << "Final Sum: " << proc.get_sum() << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/event_service/backlog.txt
1 10
2 20
3 30
14 40
15 50
-4 100
20 10
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/event_service
    chmod -R 777 /home/user
