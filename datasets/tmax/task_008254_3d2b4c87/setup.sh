#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/raw_data /home/user/tools /home/user/safe_extract /home/user/cpp_links

cat << 'EOF' > /tmp/gen_parc.py
import struct

def rle_compress(data):
    if not data: return b''
    compressed = bytearray()
    count = 1
    prev = data[0]
    for i in range(1, len(data)):
        if data[i] == prev and count < 255:
            count += 1
        else:
            compressed.extend([count, prev])
            count = 1
            prev = data[i]
    compressed.extend([count, prev])
    return bytes(compressed)

def write_parc(filename, files):
    with open(filename, 'wb') as f:
        f.write(b'PARC')
        for path, data in files:
            path_bytes = path.encode('ascii')
            f.write(struct.pack('<H', len(path_bytes)))
            f.write(path_bytes)
            comp_data = rle_compress(data)
            f.write(struct.pack('<I', len(comp_data)))
            f.write(comp_data)

write_parc('/home/user/raw_data/good.parc', [
    ('src/main.cpp', b'int main() { return 0; }'),
    ('README.md', b'Hello World!'),
    ('src/utils.cpp', b'void test() {}')
])

write_parc('/home/user/raw_data/bad.parc', [
    ('../../../../home/user/hacked.txt', b'YOU HAVE BEEN HACKED!'),
    ('src/legit.cpp', b'int legit() {}'),
    ('/etc/passwd_fake', b'root:x:0:0:')
])

write_parc('/home/user/raw_data/ignore.parc', [
    ('src/secret.cpp', b'int secret() {}')
])
EOF

python3 /tmp/gen_parc.py

cat << 'EOF' > /home/user/tools/parc_extractor.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <cstdint>
#include <sys/stat.h>

void create_directories(const std::string& path) {
    size_t pos = 0;
    while ((pos = path.find_first_of('/', pos + 1)) != std::string::npos) {
        std::string dir = path.substr(0, pos);
        mkdir(dir.c_str(), 0755);
    }
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    std::string archive_path = argv[1];
    std::string out_dir = argv[2];

    std::ifstream file(archive_path, std::ios::binary);
    if (!file) return 1;

    char magic[4];
    file.read(magic, 4);
    if (std::string(magic, 4) != "PARC") return 1;

    while (file.peek() != EOF) {
        uint16_t path_len;
        if (!file.read(reinterpret_cast<char*>(&path_len), 2)) break;

        std::string path(path_len, '\0');
        file.read(&path[0], path_len);

        uint32_t data_len;
        file.read(reinterpret_cast<char*>(&data_len), 4);

        std::vector<uint8_t> comp_data(data_len);
        file.read(reinterpret_cast<char*>(comp_data.data()), data_len);

        // TODO: Vulnerable! Need path sanitization here.

        std::string full_out_path = out_dir + "/" + path;
        create_directories(full_out_path);

        std::ofstream out(full_out_path, std::ios::binary);
        for (size_t i = 0; i < comp_data.size(); i += 2) {
            uint8_t count = comp_data[i];
            char val = comp_data[i+1];
            for (int c = 0; c < count; c++) out.put(val);
        }
    }
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod a-x /home/user/raw_data/ignore.parc
