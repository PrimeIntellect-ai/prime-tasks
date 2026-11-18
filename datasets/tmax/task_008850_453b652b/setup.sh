#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/datasets.conf
# Active dataset targets
[vision_datasets]
imagenet_subset_1
cifar10_full
# mnist_test

[nlp_datasets]
wikitext_103
# squad_v2
glue_benchmark
EOF

    cat << 'EOF' > /home/user/writer.cpp
#include <iostream>
#include <string>
#include <unistd.h>
#include <sys/file.h>
#include <fcntl.h>

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::string data = argv[1];

    int fd = open("/home/user/results.csv", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return 1;

    // TODO: Add exclusive file lock here to prevent race conditions

    for(int i = 0; i < 20; ++i) {
        std::string line = data + ",metric=" + std::to_string(i) + "\n";
        // Artificial delay to guarantee race condition if unlocked
        usleep(5000); 
        write(fd, line.c_str(), line.length());
    }

    // TODO: Release lock here

    close(fd);
    return 0;
}
EOF

    chmod -R 777 /home/user
