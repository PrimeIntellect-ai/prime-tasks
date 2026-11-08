#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    mkdir -p /home/user/src /home/user/data /home/user/bin

    cat << 'EOF' > /home/user/src/calc_energy.c
#include <stdio.h>

int main() {
    double sum = 0.0;
    double val;
    while (scanf("%lf", &val) == 1) {
        sum += val * val;
    }
    printf("%.4f\n", sum);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/test_energy.sh
#!/bin/bash
export PATH="/home/user/bin:$PATH"
if [ ! -f /home/user/bin/calc_energy ]; then
    echo "FAIL: calc_energy not found"
    exit 1
fi
res=$(echo "1.5 2.0 3.0" | calc_energy)
if [ "$res" == "15.2500" ]; then
    echo "PASS"
    exit 0
else
    echo "FAIL: expected 15.2500, got $res"
    exit 1
fi
EOF
    chmod +x /home/user/src/test_energy.sh

    cat << 'EOF' > /home/user/data/signals.txt
1.0 2.0 1.0
0.5 0.5 0.5 0.5
2.0 2.0 2.0
3.0 1.0
EOF

    cat << 'EOF' > /home/user/data/targets.txt
13.0
3.0
25.0
21.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
