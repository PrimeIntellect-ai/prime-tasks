#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest grpcio grpcio-tools

useradd -m -s /bin/bash user || true

mkdir -p /home/user/snippets

cat << 'EOF' > /home/user/snippets/1_linear.asm
mov eax, 1
add eax, 5
ret
EOF

cat << 'EOF' > /home/user/snippets/2_forward.asm
mov eax, 0
cmp eax, 10
je end
add eax, 1
end:
ret
EOF

cat << 'EOF' > /home/user/snippets/3_loop.asm
mov eax, 0
loop_start:
add eax, 1
cmp eax, 10
jne loop_start
ret
EOF

chmod -R 777 /home/user
