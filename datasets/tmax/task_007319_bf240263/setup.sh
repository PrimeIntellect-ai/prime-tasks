#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils patchelf file
    pip3 install pytest

    mkdir -p /home/user/project/bin /home/user/project/lib /home/user/project/data /home/user/syslib

    # 1. Create the data files
    echo "2.0" > "/home/user/project/data/input1.txt"
    echo "4.0" > "/home/user/project/data/input 2.txt"

    # 2. Create the libraries
    cat << 'EOF' > /home/user/syslib/mathops.c
double calculate_poly(double x, double y) {
    return x + y; // Incorrect math logic
}
EOF

    cat << 'EOF' > /home/user/project/lib/mathops.c
double calculate_poly(double x, double y) {
    return (x * x) + (y * 3.14); // Correct math logic
}
EOF

    gcc -shared -fPIC -o /home/user/syslib/libmathops.so /home/user/syslib/mathops.c
    gcc -shared -fPIC -o /home/user/project/lib/libmathops.so /home/user/project/lib/mathops.c

    # 3. Create the poly_eval binary
    cat << 'EOF' > /home/user/project/bin/poly_eval.c
#include <stdio.h>
#include <stdlib.h>

extern double calculate_poly(double x, double y);

int main(int argc, char** argv) {
    if(argc != 2) return 1;
    FILE* f = fopen(argv[1], "r");
    if(!f) return 1;
    double val;
    fscanf(f, "%lf", &val);
    fclose(f);

    // Hardcoded second parameter for simplicity
    double result = calculate_poly(val, 2.0);
    printf("%f\n", result);
    return 0;
}
EOF

    # Compile main binary linking against the SYSTEM library initially (to cause the conflict)
    gcc -o /home/user/project/bin/poly_eval /home/user/project/bin/poly_eval.c -L/home/user/syslib -lmathops -Wl,-rpath=/home/user/syslib

    # 4. Create the buggy shell script
    cat << 'EOF' > /home/user/project/run_batch.sh
#!/bin/bash
for f in $(ls /home/user/project/data/*.txt); do
    res=$(/home/user/project/bin/poly_eval $f)
    basename=$(basename $f)
    echo "$basename: $res"
done
EOF
    chmod +x /home/user/project/run_batch.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
