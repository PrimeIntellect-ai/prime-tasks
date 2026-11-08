#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/graph_engine.cpp
#include <iostream>
#include <vector>
#include <thread>
#include <mutex>
#include <algorithm>
#include <fstream>

struct Transaction {
    int src;
    int dst;
    int amount;
};

std::mutex node_locks[10];
int node_balances[10] = {1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000};
std::vector<Transaction> transactions;
std::mutex tx_lock;

void process_transaction(int src, int dst, int amount) {
    // BUG: Deadlock potential here. Needs lock ordering based on node ID (index strategy).
    node_locks[src].lock();
    std::this_thread::sleep_for(std::chrono::milliseconds(10)); // simulate work
    node_locks[dst].lock();

    if (node_balances[src] >= amount) {
        node_balances[src] -= amount;
        node_balances[dst] += amount;

        tx_lock.lock();
        transactions.push_back({src, dst, amount});
        tx_lock.unlock();
    }

    node_locks[dst].unlock();
    node_locks[src].unlock();
}

void materialize_top_transactions(int min_amount, int limit, int offset) {
    // TODO: Filter, sort, paginate, and write to /home/user/view.txt
    // Format: src,dst,amount
}

int main() {
    // Pre-seed some transactions
    transactions.push_back({5, 6, 120});
    transactions.push_back({7, 8, 40});
    transactions.push_back({3, 4, 120});

    std::thread t1(process_transaction, 1, 2, 80);
    std::thread t2(process_transaction, 2, 1, 60);
    std::thread t3(process_transaction, 0, 9, 200);

    t1.join();
    t2.join();
    t3.join();

    materialize_top_transactions(50, 3, 0);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
