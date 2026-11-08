#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/payload.cpp
#include <iostream>
const char ssh_key[] __attribute__((section(".ssh_pub"))) = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILz9m/3/RkF+wY1c7E+6x3FpZ9uE1iQ1+X1hU2+dummy fake@key";

int main() {
    std::cout << "Normal web service running..." << std::endl;
    return 0;
}
EOF

python3 -c "
with open('/home/user/traffic.dat', 'wb') as f:
    data = bytearray(b'A' * 4096)
    data[1842:1846] = b'\x7fELF'
    f.write(data)
"

mkdir -p /home/user/.ssh
touch /home/user/.ssh/authorized_keys

chmod -R 777 /home/user
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/authorized_keys
