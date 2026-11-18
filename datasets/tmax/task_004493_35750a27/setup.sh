#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make gdb
    pip3 install pytest

    mkdir -p /home/user/workspace/async_engine

    cat << 'EOF' > /home/user/workspace/async_engine/Makefile
CXX = g++
CXXFLAGS = -std=c++17 -g -Wall -pthread

all: test_cancellation

engine.o: engine.cpp engine.h
	$(CXX) $(CXXFLAGS) -c engine.cpp

test_cancellation.o: test_cancellation.cpp engine.h
	$(CXX) $(CXXFLAGS) -c test_cancellation.cpp

test_cancellation: test_cancellation.o engine.o
	$(CXX) $(CXXFLAGS) -o test_cancellation test_cancellation.o engine.o

test: test_cancellation
	./test_cancellation

clean:
	rm -f *.o test_cancellation
EOF

    cat << 'EOF' > /home/user/workspace/async_engine/engine.h
#ifndef ENGINE_H
#define ENGINE_H

#include <vector>
#include <thread>
#include <atomic>

class ExecutionEngine {
public:
    ExecutionEngine();
    ~ExecutionEngine();

    void start(int num_threads);
    void cancel();

    // Returns average processing time in milliseconds
    int get_average_processing_time();

    void add_completed_task(int time_ms);

private:
    std::vector<std::thread> workers;
    std::atomic<bool> cancelled;
    std::atomic<int> completed_tasks;
    std::atomic<int> total_time_ms;
};

#endif
EOF

    cat << 'EOF' > /home/user/workspace/async_engine/engine.cpp
#include "engine.h"
#include <chrono>

ExecutionEngine::ExecutionEngine() : cancelled(false), completed_tasks(0), total_time_ms(0) {}

ExecutionEngine::~ExecutionEngine() {
    cancel();
}

void ExecutionEngine::start(int num_threads) {
    for (int i = 0; i < num_threads; ++i) {
        workers.emplace_back([this]() {
            while (!cancelled.load()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
        });
    }
}

void ExecutionEngine::cancel() {
    cancelled.store(true);
    for (auto& worker : workers) {
        if (worker.joinable()) {
            worker.join();
        }
    }
}

void ExecutionEngine::add_completed_task(int time_ms) {
    completed_tasks++;
    total_time_ms += time_ms;
}

int ExecutionEngine::get_average_processing_time() {
    // BUG: Integer division by zero if no tasks are completed
    return total_time_ms.load() / completed_tasks.load();
}
EOF

    cat << 'EOF' > /home/user/workspace/async_engine/test_cancellation.cpp
#include "engine.h"
#include <iostream>

int main() {
    ExecutionEngine engine;
    engine.start(4);

    // Immediately cancel without completing any tasks
    engine.cancel();

    // Gather stats (this will crash due to divide-by-zero)
    int avg_time = engine.get_average_processing_time();

    std::cout << "Test passed. Average time: " << avg_time << " ms" << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
