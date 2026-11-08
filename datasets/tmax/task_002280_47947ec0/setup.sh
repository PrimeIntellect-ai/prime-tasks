#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /app/corpus/clean /app/corpus/evil

# Create the stripped binary
cat << 'EOF' > /tmp/decryptor.c
#include <stdio.h>
int main(int argc, char** argv) {
    if(argc!=2) return 1;
    FILE *f = fopen(argv[1], "r");
    if(!f) return 1;
    int c;
    while((c=fgetc(f))!=EOF) {
        putchar(c ^ 0x42);
    }
    fclose(f);
    return 0;
}
EOF
gcc -O2 -s /tmp/decryptor.c -o /app/log_decryptor
rm /tmp/decryptor.c

# Generate Clean and Evil Corpus using printf to avoid shell echo -e differences
for i in $(seq 1 10); do
    printf "[ServiceA] 1000%d Start tx_%d\n[ServiceB] 1001%d Process tx_%d\n[ServiceC] 1002%d Commit tx_%d\n" "$i" "$i" "$i" "$i" "$i" "$i" > /tmp/temp_clean.log
    /app/log_decryptor /tmp/temp_clean.log > "/app/corpus/clean/log_$i.bin"

    printf "[ServiceA] 1002%d Start tx_%d\n[ServiceB] 1001%d Process tx_%d\n[ServiceC] 1000%d Commit tx_%d\n" "$i" "$i" "$i" "$i" "$i" "$i" > /tmp/temp_evil.log
    /app/log_decryptor /tmp/temp_evil.log > "/app/corpus/evil/log_$i.bin"
done
rm -f /tmp/temp_clean.log /tmp/temp_evil.log

# Create buggy detector.sh
cat << 'EOF' > /home/user/detector.sh
#!/bin/bash
file=$1

declare -A time_A
declare -A time_B
declare -A time_C

/app/log_decryptor "$file" | while read -r service ts msg1 tx; do
    if [ "$service" = "[ServiceA]" ]; then
        time_A[$tx]=$ts
    elif [ "$service" = "[ServiceB]" ]; then
        time_B[$tx]=$ts
    elif [ "$service" = "[ServiceC]" ]; then
        time_C[$tx]=$ts
    fi
done

# Bug 1: Variables time_A, time_B, time_C are empty here because the while loop ran in a pipe subshell.
# Bug 2: The comparison below uses lexicographical string comparison (<) instead of integer comparison (-lt).

for tx in "${!time_A[@]}"; do
    ta=${time_A[$tx]}
    tb=${time_B[$tx]}
    tc=${time_C[$tx]}

    if [[ "$tb" < "$ta" || "$tc" < "$tb" ]]; then
        exit 1
    fi
done

exit 0
EOF
chmod +x /home/user/detector.sh
chown -R user:user /home/user/detector.sh

chmod -R 777 /home/user
