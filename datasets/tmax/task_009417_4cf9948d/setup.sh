#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/math_helper.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if(argc != 4) return 1;
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    int c = atoi(argv[3]);

    // String left for RE
    const char* hint = "FATAL: Crash occurs when A + B = C (denominator becomes zero).";

    int denom = a + b - c;
    if (denom == 0) {
        int crash = 1 / denom; // Triggers SIGFPE
        printf("%d", crash);
    }

    printf("%d\n", 10000 / denom);
    return 0;
}
EOF

    gcc -O0 /home/user/math_helper.c -o /home/user/math_helper
    rm /home/user/math_helper.c

    cat << 'EOF' > /home/user/calculate_risk.sh
#!/bin/bash
# calculate_risk.sh

while IFS=',' read -r a b c; do
    # Skip header
    if [[ "$a" == "A" ]]; then continue; fi

    echo "Processing $a, $b, $c"
    /home/user/math_helper "$a" "$b" "$c"

    if [ $? -ne 0 ]; then
        echo "Error processing row: $a,$b,$c"
        exit 1
    fi
done < /home/user/data.csv
EOF
    chmod +x /home/user/calculate_risk.sh

    cat << 'EOF' > /home/user/data.csv
A,B,C
10,20,5
15,10,2
30,20,50
8,12,10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
