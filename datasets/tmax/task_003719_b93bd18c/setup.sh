#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/custom_crypto.h
#ifndef CUSTOM_CRYPTO_H
#define CUSTOM_CRYPTO_H

#include <string>
#include <iomanip>
#include <sstream>

// Custom FNV-1a based weak hashing
inline std::string custom_hash(const std::string& input) {
    unsigned int hash = 0x811c9dc5;
    for (char c : input) {
        hash ^= static_cast<unsigned char>(c);
        hash *= 0x01000193;
    }
    std::stringstream ss;
    ss << std::hex << std::setw(8) << std::setfill('0') << hash;
    return ss.str();
}

inline std::string generate_token(const std::string& username, const std::string& password) {
    // Format: username||password||STATIC_SALT
    std::string data = username + "||" + password + "||SECURE_SALT_99";
    return custom_hash(data);
}

#endif // CUSTOM_CRYPTO_H
EOF

cat << 'EOF' > /home/user/wordlist.txt
password123
admin123
hunter2
sunshine
p@ssw0rd2023
qwerty
letmein1
EOF

python3 -c '
def fnv1a(text):
    h = 0x811c9dc5
    for c in text:
        h ^= ord(c)
        h = (h * 0x01000193) & 0xFFFFFFFF
    return f"{h:08x}"
token = fnv1a("admin||p@ssw0rd2023||SECURE_SALT_99")
with open("/home/user/admin_token.txt", "w") as f:
    f.write(token)
'

chmod -R 777 /home/user
