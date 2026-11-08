#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/ticket_4092
    cd /home/user/ticket_4092

    # Create Makefile
    cat << 'EOF' > Makefile
all:
	g++ -std=c++17 -Wall sensor_parser.cpp -o sensor_parser
EOF

    # Create broken C++ code
    cat << 'EOF' > sensor_parser.cpp
#include <iostream>
#include <fstream>
#include <stdexcept>
#include <iomanip>
// BUG 1: Missing <cstdint> and <vector> (vector not strictly needed but good for trap)

struct Record {
    uint16_t id;
    int16_t temp_dc;
} __attribute__((packed));

int main() {
    std::ifstream file("sensor_data.bin", std::ios::binary);
    if (!file) {
        std::cerr << "Cannot open file\n";
        return 1;
    }

    char magic[4];
    file.read(magic, 4);
    if (std::string(magic, 4) != "SENS") { // BUG 1.5: Missing <string>
        std::cerr << "Invalid magic\n";
        return 1;
    }

    int sum = 0;
    int count = 0;

    while (file) {
        uint8_t marker;
        file.read((char*)&marker, 1);
        if (file.eof()) break;

        if (marker != 0xFF) {
            // BUG 2: Crashes on corrupted input instead of resyncing
            throw std::runtime_error("Corrupted record marker encountered!");
        }

        Record r;
        file.read((char*)&r, sizeof(r));
        if (file.eof()) break;

        sum += r.temp_dc;
        count++;
    }

    // BUG 3: Integer division and missing deci-Celsius to Celsius conversion
    float avg = sum / count;

    // Output should go to report.txt, not stdout
    std::cout << "Average Temperature: " << std::fixed << std::setprecision(2) << avg << " C\n";
    std::cout << "Valid Records: " << count << "\n";

    return 0;
}
EOF

    # Create the binary data file using Python
    python3 -c '
import struct

with open("sensor_data.bin", "wb") as f:
    f.write(b"SENS")

    # Valid Record 1: ID 1, Temp 20.0 C (200)
    f.write(struct.pack("<B h h", 0xFF, 1, 200))

    # Valid Record 2: ID 2, Temp 21.5 C (215)
    f.write(struct.pack("<B h h", 0xFF, 2, 215))

    # Corrupted bytes (3 bytes of garbage)
    f.write(b"\xDE\xAD\xBE")

    # Valid Record 3: ID 3, Temp 22.4 C (224)
    f.write(struct.pack("<B h h", 0xFF, 3, 224))

    # More garbage
    f.write(b"\x00\x11")

    # Valid Record 4: ID 4, Temp 18.0 C (180)
    f.write(struct.pack("<B h h", 0xFF, 4, 180))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
