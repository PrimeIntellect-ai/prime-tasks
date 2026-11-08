#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make build-essential
pip3 install pytest

mkdir -p /home/user/project
cd /home/user/project

cat << 'EOF' > c.c
int funcC() { return 42; }
EOF

cat << 'EOF' > b.c
extern int funcC();
int funcB() { return funcC() + 1; }
EOF

cat << 'EOF' > a.c
extern int funcB();
int funcA() { return funcB() + 1; }
EOF

cat << 'EOF' > main.c
#include <stdio.h>
extern int funcA();
int main() {
    printf("Result: %d\n", funcA());
    return 0;
}
EOF

cat << 'EOF' > deps.json
{
  "A": ["B"],
  "B": ["C"],
  "C": []
}
EOF

cat << 'EOF' > Makefile
all: app

libC.a: c.o
TABar rcs libC.a c.o

libB.a: b.o
TABar rcs libB.a b.o

libA.a: a.o
TABar rcs libA.a a.o

EOF

sed -i 's/^TAB/\t/' Makefile

printf '%%.o: %%.c\n\tgcc -c $< -o $@\n\n' >> Makefile

cat << 'EOF' >> Makefile
app: main.o libA.a libB.a libC.a
TABgcc main.o -L. -lC -lB -lA -o app
EOF

sed -i 's/^TAB/\t/' Makefile

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
