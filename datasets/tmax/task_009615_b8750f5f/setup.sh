#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gcc binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create wordlist
    cat << 'EOF' > /home/user/wordlist.txt
charlie123
redteam2024
hunter2
supersecret
shadowoperat0r
EOF

    # 2. Generate RSA Key protected with password "shadowoperat0r"
    openssl genrsa -aes256 -passout pass:shadowoperat0r -out /home/user/target_key.pem 2048

    # 3. Extract Public Key
    openssl rsa -in /home/user/target_key.pem -passin pass:shadowoperat0r -pubout -out /home/user/target_pub.pem

    # 4. Generate random symmetric key and encrypt it with the RSA public key
    echo -n "aes_master_key_9912" > /home/user/sym_key.txt
    openssl pkeyutl -encrypt -pubin -inkey /home/user/target_pub.pem -in /home/user/sym_key.txt -out /home/user/sym_key.enc

    # 5. Create dummy ELF and add custom section
    echo 'int main() { return 0; }' > /home/user/dummy.c
    gcc /home/user/dummy.c -o /home/user/dummy.elf
    echo -n "https://10.10.99.55:4444/callback" > /home/user/c2_data.bin
    objcopy --add-section .c2_config=/home/user/c2_data.bin /home/user/dummy.elf /home/user/payload_raw.elf

    # 6. Encrypt the ELF payload
    openssl enc -aes-256-cbc -pbkdf2 -salt -in /home/user/payload_raw.elf -out /home/user/payload.enc -pass pass:aes_master_key_9912

    # 7. Cleanup intermediate/secret files
    rm /home/user/target_pub.pem /home/user/sym_key.txt /home/user/dummy.c /home/user/dummy.elf /home/user/c2_data.bin /home/user/payload_raw.elf

    chmod -R 777 /home/user
