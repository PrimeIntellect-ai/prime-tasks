#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git gcc make
pip3 install pytest

mkdir -p /home/user/repo
cd /home/user/repo
git init
git config user.email "dev@example.com"
git config user.name "Dev"

cat << 'EOF' > process_data.c
#include <stdio.h>
int main() { 
    /* Convergence stable */
    return 0; 
}
EOF
cat << 'EOF' > Makefile
process_data: process_data.c
	gcc -o process_data process_data.c
clean:
	rm -f process_data
EOF
git add process_data.c Makefile
git commit -m "Initial commit: Add working data processor"

for i in 1 2 3; do
  echo "// Routine update $i" >> process_data.c
  git commit -am "Update data processor logic part $i"
done

cat << 'EOF' > process_data.c
#include <stdio.h>
int main() { 
    /* Convergence failure due to serialization mismatch */
    return 1; 
}
EOF
git commit -am "Refactor serialization logic"
BAD_COMMIT=$(git rev-parse HEAD)

for i in 4 5 6 7; do
  echo "// Routine update $i" >> process_data.c
  git commit -am "Update data processor logic part $i"
done

dd if=/dev/urandom of=/home/user/crash.dmp bs=1K count=50 2>/dev/null
echo -n "FATAL_ENC_ERR_77A90F1B" >> /home/user/crash.dmp
dd if=/dev/urandom of=/home/user/crash.dmp bs=1K count=50 oflag=append conv=notrunc 2>/dev/null

mkdir -p /home/user/expected
echo "$BAD_COMMIT" > /home/user/expected/commit.txt
echo "FATAL_ENC_ERR_77A90F1B" > /home/user/expected/error.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
