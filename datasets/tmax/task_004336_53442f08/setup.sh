#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        g++ make libssl-dev \
        imagemagick tesseract-ocr \
        fonts-dejavu-core

    pip3 install --default-timeout=100 pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean
    mkdir -p /home/user/log_tool
    mkdir -p /home/user/samples

    # Generate the ticket attachment image
    convert -background black -fill white -font DejaVu-Sans -pointsize 18 label:"g++ -o parser main.o log_utils.o\nlog_utils.o: In function \`HashCheck(char const*)':\nlog_utils.cpp:(.text+0x42): undefined reference to \`EVP_md5'\nlog_utils.cpp:(.text+0x57): undefined reference to \`EVP_DigestInit_ex'\ncollect2: error: ld returned 1 exit status" /app/ticket_attachment.png

    # Create C++ source files
    cat << 'EOF' > /home/user/log_tool/main.cpp
#include <iostream>
#include <string>
#include <fstream>

void HashCheck(const char*);
void parse_line(const std::string& line);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream infile(argv[1]);
    std::string line;
    while (std::getline(infile, line)) {
        HashCheck(line.c_str());
        parse_line(line);
    }
    return 0;
}

void parse_line(const std::string& line) {
    const char* str = line.c_str();
    int i = 0;
    while (str[i] != '\0') {
        if (str[i] == '"') {
            i++;
            while (str[i] != '"' && str[i] != '\0') {
                if (str[i] == '\\') {
                    i++; // skips next char, even if it's \0!
                }
                i++;
            }
        }
        if (str[i] != '\0') i++;
    }
}
EOF

    cat << 'EOF' > /home/user/log_tool/log_utils.cpp
#include <openssl/evp.h>
#include <iostream>

void HashCheck(const char* data) {
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(mdctx, EVP_md5(), NULL);
    EVP_MD_CTX_free(mdctx);
}
EOF

    cat << 'EOF' > /home/user/log_tool/Makefile
parser: main.o log_utils.o
	g++ -o parser main.o log_utils.o

main.o: main.cpp
	g++ -c main.cpp

log_utils.o: log_utils.cpp
	g++ -c log_utils.cpp

clean:
	rm -f *.o parser
EOF

    # Create corpora
    cat << 'EOF' > /app/corpus/evil/evil1.txt
INFO: User input "weird\
EOF
    cat << 'EOF' > /app/corpus/evil/evil2.txt
ERROR: Something went wrong "and here is a backslash\
EOF

    cat << 'EOF' > /app/corpus/clean/clean1.txt
INFO: Normal line
DEBUG: User "test" logged in
WARN: Path is "C:\\Windows\\System32"
EOF

    # Create samples
    cat << 'EOF' > /home/user/samples/sample.log
INFO: Normal line
INFO: User input "weird\
DEBUG: User "test" logged in
ERROR: Something went wrong "and here is a backslash\
WARN: Path is "C:\\Windows\\System32"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
