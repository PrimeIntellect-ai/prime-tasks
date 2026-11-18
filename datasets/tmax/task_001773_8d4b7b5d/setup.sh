#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo -n "ITERATIONS=1000" | base64 > /home/user/math_config.b64

    cat << 'EOF' > /home/user/helper.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if(argc != 2) return 1;
    double i = atof(argv[1]);
    // Uses pow() to intentionally require the math library (-lm)
    double denom = pow(2.0 * i + 1.0, 1.0);
    printf("%.6f\n", 1.0 / denom);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/calc_pi.sh
#!/bin/bash

# BUG 1: Missing base64 decoding
CONFIG=$(cat /home/user/math_config.b64)
ITERATIONS=$(echo "$CONFIG" | grep -oP 'ITERATIONS=\K\d+')

# BUG 2: Missing linker flag -lm
gcc -o term_calc /home/user/helper.c

PI=0
SIGN=1

for i in $(seq 0 $ITERATIONS); do
    TERM=$(./term_calc $i)

    PI=$(echo "scale=6; $PI + ($SIGN * $TERM)" | bc)

    # BUG 3: Missing sign alternation for the Gregory-Leibniz series
    # Expected fix: SIGN=$((SIGN * -1))
done

echo "scale=4; $PI * 4" | bc > /home/user/pi_result.txt
EOF

    chmod +x /home/user/calc_pi.sh

    chmod -R 777 /home/user
