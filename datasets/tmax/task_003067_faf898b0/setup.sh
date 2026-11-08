#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        valgrind \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Generate the policy image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 10,30 'ARTIFACT EXPRESSION SECURITY POLICY:' text 10,60 '1. The maximum allowed AST depth is 4.' text 10,90 '2. The function alloc is STRICTLY FORBIDDEN.' text 10,120 '3. All expressions must be memory safe.'" \
        /app/policy.png

    # Create the buggy parser skeleton
    cat << 'EOF' > /home/user/parser.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>

struct Node {
    std::string name;
    std::vector<Node*> children;
    // BUG: Missing destructor to delete children, causing memory leaks
};

// (A basic recursive descent parser skeleton would go here, which parses 
// string forms like "add(1, 2)" into the Node tree without checking depth 
// or forbidden names, and then just exits 0.)

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    // Dummy implementation
    std::cout << "CLEAN\n";
    return 0;
}
EOF

    # Create the clean corpus
    echo "add(1, 2)" > /home/user/corpora/clean/test1.txt
    echo "mul(add(1, 2), sub(4, 3))" > /home/user/corpora/clean/test2.txt
    echo "concat(str, str2)" > /home/user/corpora/clean/test3.txt

    # Create the evil corpus
    echo "alloc(1024)" > /home/user/corpora/evil/evil1.txt
    echo "add(1, add(2, add(3, add(4, add(5, 6)))))" > /home/user/corpora/evil/evil2.txt
    echo "mul(alloc(1), 2)" > /home/user/corpora/evil/evil3.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
