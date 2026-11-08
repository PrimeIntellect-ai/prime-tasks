#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip g++
    pip3 install pytest Pillow

    # Create app directory
    mkdir -p /app

    # Create memo.png
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 40), 'The archive password is: Audit2024!', fill=(0, 0, 0))
img.save('/app/memo.png')
"

    # Create user home
    useradd -m -s /bin/bash user || true

    # Create redact.cpp
    cat << 'EOF' > /tmp/redact.cpp
#include <iostream>
#include <fstream>
#include <regex>
#include <string>

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <input_file> <output_file>\n";
        return 1;
    }
    std::ifstream in(argv[1]);
    std::ofstream out(argv[2]);
    std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());

    // Slow regex for 16-digit credit cards with optional spaces/dashes
    std::regex cc_regex(R"(\b(?:\d[ -]*){15}\d\b)");
    out << std::regex_replace(content, cc_regex, "[REDACTED]");

    return 0;
}
EOF

    # Create sample.log
    cat << 'EOF' > /tmp/sample.log
System boot up...
User login: admin
Processing payment for card: 1234-5678-9012-3456
Payment successful.
Another transaction: 1234 5678 9012 3456
Plain format: 1234567890123456
End of log.
EOF

    # Create encrypted zip
    cd /tmp
    zip -P Audit2024! /home/user/audit_archive.zip redact.cpp sample.log

    # Create sshd_config
    cat << 'EOF' > /home/user/sshd_config
# SSH Server Configuration
Port 22
PermitRootLogin yes
PasswordAuthentication yes
X11Forwarding yes
EOF

    chmod -R 777 /home/user
