#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat binutils curl
    pip3 install pytest

    mkdir -p /home/user/mobile_build
    cd /home/user/mobile_build

    cat << 'EOF' > libmath_alpha.c
int calculate_metric(int input) {
    return input * 2;
}
EOF

    cat << 'EOF' > libmath_beta.c
int calculate_metric(int input) {
    return input * input;
}
int beta_specific_math() {
    return 42;
}
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
int calculate_metric(int);
int main() {
    printf("%d\n", calculate_metric(5));
    return 0;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
gcc -shared -fPIC -o libmath_alpha.so libmath_alpha.c
gcc -shared -fPIC -o libmath_beta.so libmath_beta.c
gcc main.c -o app -L. -lmath_beta -lmath_alpha -Wl,-rpath=.
EOF
    chmod +x build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
