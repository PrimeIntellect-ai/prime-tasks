#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake gcc g++ make ruby
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace/builder/src
    mkdir -p /home/user/workspace/builder/build

    cat << 'EOF' > /home/user/workspace/builder/src/archiver.c
#include <stdio.h>

unsigned char compute_checksum(const char* filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) return 0;
    unsigned char sum = 0;
    int c;
    while ((c = fgetc(f)) != EOF) {
        sum ^= c;
    }
    fclose(f);
    return sum;
}
EOF

    cat << 'EOF' > /home/user/workspace/builder/src/packager.c
#include <stdio.h>

extern unsigned char compute_checksum(const char* filename);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    printf("%02x\n", compute_checksum(argv[1]));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/workspace/builder/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(ArtifactBuilder C)

add_library(archiver SHARED src/archiver.c)
add_executable(packager src/packager.c)

# MISSING: target_link_libraries(packager archiver)
# MISSING: set_target_properties(packager PROPERTIES BUILD_RPATH "$ORIGIN")
EOF

    cat << 'EOF' > /home/user/workspace/artifacts.json
[
  {
    "id": "item-1",
    "filepath": "builder/src/archiver.c",
    "type": "source"
  },
  {
    "id": "item-2",
    "filepath": "builder/src/packager.c",
    "type": "source"
  }
]
EOF

    cat << 'EOF' > /home/user/workspace/legacy_manifest.rb
require 'json'

input_file = 'artifacts.json'
data = JSON.parse(File.read(input_file))

v2_manifest = {
  "version" => 2,
  "artifacts" => {}
}

data.each do |item|
  id = item["id"]
  v2_manifest["artifacts"][id] = {
    "file" => item["filepath"],
    "category" => item["type"],
    "checksum" => "PENDING"
  }
end

puts JSON.pretty_generate(v2_manifest)
EOF

    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
