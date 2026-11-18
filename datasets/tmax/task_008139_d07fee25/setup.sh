#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libssl-dev bubblewrap xxd openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the key
    echo -n "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" > /home/user/key.txt

    # Create the C++ file
    cat << 'EOF' > /home/user/audit_parser.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstring>
#include <openssl/evp.h>

void parse_record(const std::string& record, std::ofstream& out) {
    // VULNERABILITY: Stack-based buffer overflow
    char buffer[64];
    strcpy(buffer, record.c_str()); 
    out << "AUDIT_RECORD: " << buffer << "\n";
}

unsigned char hex_to_byte(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

int main(int argc, char** argv) {
    if(argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <input_file> <output_file> <hex_key>\n";
        return 1;
    }

    std::string hex_key = argv[3];
    if (hex_key.length() != 64) {
        std::cerr << "Key must be 64 hex characters.\n";
        return 1;
    }

    unsigned char key[32];
    for(int i=0; i<32; ++i) {
        key[i] = (hex_to_byte(hex_key[i*2]) << 4) | hex_to_byte(hex_key[i*2+1]);
    }

    std::ifstream in(argv[1], std::ios::binary);
    if (!in) return 1;

    unsigned char iv[16];
    in.read((char*)iv, 16);

    std::vector<unsigned char> ciphertext((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    in.close();

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, key, iv);

    std::vector<unsigned char> plaintext(ciphertext.size() + EVP_MAX_BLOCK_LENGTH);
    int len = 0, plaintext_len = 0;

    EVP_DecryptUpdate(ctx, plaintext.data(), &len, ciphertext.data(), ciphertext.size());
    plaintext_len = len;

    EVP_DecryptFinal_ex(ctx, plaintext.data() + len, &len);
    plaintext_len += len;

    EVP_CIPHER_CTX_free(ctx);

    std::string decrypted((char*)plaintext.data(), plaintext_len);

    std::ofstream out(argv[2]);
    if (!out) return 1;

    size_t pos = 0;
    while ((pos = decrypted.find('\n')) != std::string::npos) {
        std::string line = decrypted.substr(0, pos);
        parse_record(line, out);
        decrypted.erase(0, pos + 1);
    }
    if (!decrypted.empty()) {
        parse_record(decrypted, out);
    }

    out.close();
    return 0;
}
EOF

    # Create the encrypted log
    KEY="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    IV="fedcba9876543210fedcba9876543210"
    echo -e "This is a very long audit log entry that will definitely overflow the sixty-four byte buffer if it is not properly handled by the parsing function.\nAnother long line for the audit log that exceeds the buffer size limit and causes a crash." > /tmp/plain.txt

    openssl enc -aes-256-cbc -K $KEY -iv $IV -in /tmp/plain.txt -out /tmp/enc.dat

    # Prepend IV to the encrypted file
    echo -n $IV | xxd -r -p > /home/user/encrypted_logs.dat
    cat /tmp/enc.dat >> /home/user/encrypted_logs.dat

    chmod -R 777 /home/user
