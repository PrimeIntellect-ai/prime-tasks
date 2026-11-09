#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils diffutils
    pip3 install pytest

    mkdir -p /home/user/firmware

    cat << 'EOF' > /home/user/firmware/app.c
int main() {
    int a = 5;
    int b = 10;
    return a + b;
}
EOF

    cat << 'EOF' > /home/user/firmware/boot.S
.global _start
_start:
    mov $1, %eax
    xor %ebx, %ebx
    int $0x80
EOF

    cd /home/user/firmware
    gcc -c app.c -o app.o
    gcc -c boot.S -o boot.o
    objcopy -O binary app.o app.bin
    objcopy -O binary boot.o boot.bin

    python3 -c '
def fletcher16(data):
    sum1 = 0
    sum2 = 0
    for byte in data:
        sum1 = (sum1 + byte) % 255
        sum2 = (sum2 + sum1) % 255
    return (sum2 << 8) | sum1

with open("app.bin", "rb") as f: app_data = f.read()
with open("boot.bin", "rb") as f: boot_data = f.read()

app_csum = f"{fletcher16(app_data):04X}"
boot_csum = f"{fletcher16(boot_data):04X}"

with open("/home/user/manifest_v1.txt", "w") as f:
    f.write(f"app.bin: 0000\n")
    f.write(f"boot.bin: {boot_csum}\n")
'

    rm app.o boot.o app.bin boot.bin
    cd /home/user

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
