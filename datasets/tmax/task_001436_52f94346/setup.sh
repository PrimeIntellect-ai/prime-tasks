#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev diffutils
    pip3 install pytest

    mkdir -p /home/user/project
    cat << 'EOF' > /home/user/project/compute.c
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    FILE *f = fopen("input.txt", "r");
    if (!f) return 1;
    FILE *out = fopen("output.txt", "w");
    if (!out) return 1;
    double a, b, c;
    while (fscanf(f, "%lf %lf %lf", &a, &b, &c) == 3) {
        // BUG: discriminant should be b*b - 4*a*c
        double discriminant = b*b + 4*a*c;
        if (discriminant < 0) {
            fprintf(out, "NaN\n");
        } else {
            double root1 = (-b + sqrt(discriminant)) / (2*a);
            double root2 = (-b - sqrt(discriminant)) / (2*a);
            // Ensure root1 >= root2 for consistent output
            if (root1 < root2) {
                double temp = root1;
                root1 = root2;
                root2 = temp;
            }
            fprintf(out, "%.4f %.4f\n", root1, root2);
        }
    }
    fclose(f);
    fclose(out);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/input.txt
1 -3 2
1 -5 6
1 0 -4
1 -2 1
EOF

    cat << 'EOF' > /home/user/project/expected.txt
2.0000 1.0000
3.0000 2.0000
2.0000 -2.0000
1.0000 1.0000
EOF

    cat << 'EOF' > /home/user/project/test.sh
#!/bin/bash
cd /home/user/project
gcc compute.c -o compute -lm
if [ $? -ne 0 ]; then
    echo "COMPILATION FAILED"
    exit 1
fi
./compute
diff output.txt expected.txt > diff.log
if [ $? -eq 0 ]; then
    echo "BUILD SUCCESS"
    exit 0
else
    echo "BUILD FAILED"
    cat diff.log
    exit 1
fi
EOF
    chmod +x /home/user/project/test.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
