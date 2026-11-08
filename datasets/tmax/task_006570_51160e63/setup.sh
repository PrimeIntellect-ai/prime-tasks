#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils libc6-dev
    pip3 install pytest

    mkdir -p /home/user/project/libs

    cat << 'EOF' > /home/user/project/libs/libalpha.c
const char* get_alpha_version() {
    return "2.1.5";
}
EOF

    cat << 'EOF' > /home/user/project/libs/libbeta.c
#include <stdio.h>
void beta_init() {
    printf("Beta library initialized.\n");
}
EOF

    # Compile the shared libraries
    gcc -shared -fPIC -o /home/user/project/libs/libalpha.so /home/user/project/libs/libalpha.c
    gcc -shared -fPIC -o /home/user/project/libs/libbeta.so /home/user/project/libs/libbeta.c

    cat << 'EOF' > /home/user/project/app.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern const char* get_alpha_version();
extern void beta_init();

// BUGGY IMPLEMENTATION - Buffer overflow
int compare_semver(const char* v1, const char* v2) {
    char buf1[6];
    char buf2[6];

    // Memory safety vulnerability here:
    strcpy(buf1, v1);
    strcpy(buf2, v2);

    int major1, minor1, patch1;
    int major2, minor2, patch2;

    sscanf(buf1, "%d.%d.%d", &major1, &minor1, &patch1);
    sscanf(buf2, "%d.%d.%d", &major2, &minor2, &patch2);

    if (major1 != major2) return major1 - major2;
    if (minor1 != minor2) return minor1 - minor2;
    return patch1 - patch2;
}

int main(int argc, char** argv) {
    beta_init();
    const char* ver = (argc > 1) ? argv[1] : get_alpha_version();

    int res = compare_semver(ver, "2.1.0");
    if (res >= 0) {
        printf("Version OK: %s\n", ver);
        return 0;
    } else {
        printf("Version too old: %s\n", ver);
        return 1;
    }
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
all: app

app: app.c
	gcc -o app app.c -L./libs -lalpha -lbeta
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
