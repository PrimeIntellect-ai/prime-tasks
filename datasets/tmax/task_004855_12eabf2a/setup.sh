#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import struct

os.makedirs("/home/user/sensor_data", exist_ok=True)

for i in range(50):
    filepath = f"/home/user/sensor_data/file_{i:02d}.dat"
    with open(filepath, "wb") as f:
        if i % 10 == 0:
            data = [30000, -30000, 30000, -30000, 30000, -30000]
        else:
            data = [10, 12, 11, 9, 10, 15]

        for val in data:
            f.write(struct.pack("<h", val))

cpp_code = """#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <cstdlib>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;

    const char* conf = std::getenv("SENSOR_CONF");
    std::string conf_path = conf ? conf : std::string(std::getenv("HOME")) + "/.local/share/sensor/default.conf";

    std::ifstream cfile(conf_path);
    if (!cfile) {
        std::cerr << "Warning: could not open config file." << std::endl;
    }

    std::ifstream in(argv[1], std::ios::binary);
    std::vector<int16_t> data;
    int16_t val;
    while (in.read(reinterpret_cast<char*>(&val), sizeof(val))) {
        data.push_back(val);
    }

    if (data.empty()) return 0;

    long long sum = 0;
    for (auto v : data) sum += v;
    long long mean = sum / (long long)data.size();

    long long variance_sum = 0;
    for (auto v : data) {
        int diff = v - mean; 
        int sq = diff * diff; // BUG: 32-bit signed integer overflow
        variance_sum += sq; 
    }

    std::cout << argv[1] << " Mean:" << mean << " VarSum:" << variance_sum << std::endl;
    return 0;
}
"""

with open("/home/user/processor.cpp", "w") as f:
    f.write(cpp_code)

sh_code = """#!/bin/bash
for f in /home/user/sensor_data/*.dat; do
    /home/user/processor "$f"
done
"""
with open("/home/user/run_all.sh", "w") as f:
    f.write(sh_code)
os.chmod("/home/user/run_all.sh", 0o755)
'

    chmod -R 777 /home/user
