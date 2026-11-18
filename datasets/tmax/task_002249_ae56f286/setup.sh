#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick gcc make fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    # Fix ImageMagick policy to allow text/draw if needed, but default is usually fine for these.
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'Formula: y = 14x^2 - 3x + 19'" /app/formula.png

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/helper.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double val = atof(argv[1]);
    printf("%.0f\n", pow(val, 2.0));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
helper: helper.c
	gcc -O2 helper.c -o helper
EOF

    cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash
# Broken pipeline
x=$1
# Incorrect formula
sq=$(/home/user/src/helper $x 2>/dev/null || echo 0)
y=$(( 5 * sq + 2 * x - 10 ))
echo $y
EOF
    chmod +x /home/user/pipeline.sh

    cat << 'EOF' > /app/oracle_calc.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    long long x = atoll(argv[1]);
    long long y = 14 * x * x - 3 * x + 19;
    printf("%lld\n", y);
    return 0;
}
EOF
    gcc -O2 /app/oracle_calc.c -o /app/oracle_calc
    chmod +x /app/oracle_calc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
