#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/kv_store

cat << 'EOF' > /home/user/kv_store/kv_store.h
#ifndef KVSTORE_H
#define KVSTORE_H

#include <map>
#include <string>
#include <mutex>

class KVStore {
private:
    std::map<std::string, std::string> store;
    std::mutex mtx;
public:
    void put(const std::string& key, const std::string& value);
    std::string get(const std::string& key);
};

#endif
EOF

cat << 'EOF' > /home/user/kv_store/kv_store.cpp
#include "kv_store.h"

void KVStore::put(const std::string& key, const std::string& value) {
    // BUG: Missing synchronization here
    store[key] = value;
}

std::string KVStore::get(const std::string& key) {
    std::lock_guard<std::mutex> lock(mtx);
    if (store.find(key) != store.end()) {
        return store[key];
    }
    return "";
}
EOF

cat << 'EOF' > /home/user/kv_store/main.cpp
#include "kv_store.h"
#include <thread>
#include <vector>

void worker(KVStore& kvs, int id) {
    for (int i = 0; i < 1000; ++i) {
        kvs.put("key" + std::to_string(id) + "_" + std::to_string(i), "val");
    }
}

int main() {
    KVStore kvs;
    std::vector<std::thread> threads;
    for (int i = 0; i < 10; ++i) {
        threads.emplace_back(worker, std::ref(kvs), i);
    }
    for (auto& t : threads) {
        t.join();
    }
    return 0;
}
EOF

cat << 'EOF' > /home/user/kv_store/Makefile
all: stress_test

stress_test: main.cpp kv_store.cpp
	g++ -O3 -pthread -std=c++11 main.cpp kv_store.cpp -o stress_test

clean:
	rm -f stress_test
EOF

cat << 'EOF' > /tmp/gen_wal.py
import struct

entries = [
    (b"foo", b"bar"),
    (b"hello", b"world"),
    (b"test", b"123")
]

with open("/home/user/kv_store/data.wal", "wb") as f:
    for k, v in entries:
        f.write(struct.pack('B', 0xAA))
        f.write(struct.pack('B', len(k)))
        f.write(k)
        f.write(struct.pack('B', len(v)))
        f.write(v)
        f.write(struct.pack('B', 0xBB))

    # Corrupt entry
    f.write(struct.pack('B', 0xAA))
    f.write(struct.pack('B', 4))
    f.write(b"corr")
    f.write(struct.pack('B', 2))
    f.write(b"up")
    # missing 0xBB
EOF

python3 /tmp/gen_wal.py
rm /tmp/gen_wal.py

chmod -R 777 /home/user
