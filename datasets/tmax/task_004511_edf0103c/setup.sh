#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/build_router
    cd /home/user/build_router

    cat << 'EOF' > main.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int compare_versions(const char* v1, const char* v2);
char* parse_arch(const char* url);

int main(int argc, char** argv) {
    if (argc < 2) return 1;

#ifdef CROSS_COMPILE_MODE
    printf("[CROSS COMPILE MODE ENABLED]\n");
#endif

    if (strcmp(argv[1], "semver") == 0 && argc == 4) {
        int res = compare_versions(argv[2], argv[3]);
        printf("%d\n", res);
        return 0;
    }

    if (strcmp(argv[1], "parse") == 0 && argc == 3) {
        char* arch = parse_arch(argv[2]);
        if (arch) {
            printf("ARCH: %s\n", arch);
            free(arch);
        } else {
            printf("ARCH: NONE\n");
        }
        return 0;
    }

    return 1;
}
EOF

    cat << 'EOF' > semver.c
#include <string.h>

int compare_versions(const char* v1, const char* v2) {
    // BUG: Naive string comparison fails for 1.10.0 vs 1.2.0
    int res = strcmp(v1, v2);
    if (res > 0) return 1;
    if (res < 0) return -1;
    return 0;
}
EOF

    cat << 'EOF' > url_parser.c
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

char* parse_arch(const char* url) {
    // BUG: strstr returns NULL if not found, causing segfault on +6
    char* query = strstr(url, "?arch=");
    char* arch = strdup(query + 6);
    return arch;
}
EOF

    cat << 'EOF' > Makefile
CC = gcc
CFLAGS = -Wall -Wextra

# BUG: Missing conditional for ARCH=cross
# BUG: Missing url_parser.o in the target

all: router

router: main.o semver.o
	$(CC) $(CFLAGS) -o router main.o semver.o url_parser.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

semver.o: semver.c
	$(CC) $(CFLAGS) -c semver.c

url_parser.o: url_parser.c
	$(CC) $(CFLAGS) -c url_parser.c

clean:
	rm -f *.o router
EOF

    cat << 'EOF' > benchmark.sh
#!/bin/bash
for i in {1..5000}; do
    ./router parse "build://project/1.0.$i?arch=x86_64" > /dev/null
done
echo "Benchmark completed: 5000 requests processed."
EOF
    chmod +x benchmark.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/build_router
    chmod -R 777 /home/user
