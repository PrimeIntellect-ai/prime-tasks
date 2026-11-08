#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc patch
pip3 install pytest

# Create the vendor binary
mkdir -p /app
cat << 'EOF' > /app/vendor_eval.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *py_code = "import sys\n"
                    "s = sys.argv[1].replace('MOD', 'mod_func').replace('SUM_SQ', 'sum_sq_func').replace('/', '//')\n"
                    "mod_func = lambda a, b: a % b\n"
                    "sum_sq_func = lambda a, b: a*a + b*b\n"
                    "try:\n"
                    "    print(eval(s))\n"
                    "except Exception:\n"
                    "    pass\n";
    execlp("python3", "python3", "-c", py_code, argv[1], NULL);
    return 1;
}
EOF
gcc -O3 -o /app/vendor_eval /app/vendor_eval.c
strip /app/vendor_eval
chmod +x /app/vendor_eval

# Create data directory and files
mkdir -p /home/user/data
cat << 'EOF' > /home/user/data/base_expressions.txt
1 + 2
3 * 4
10 / 2
SUM_SQ(3, 4)
MOD(10, 3)
EOF

cat << 'EOF' > /home/user/data/updates.patch
--- base_expressions.txt
+++ base_expressions.txt
@@ -3,3 +3,4 @@
 10 / 2
 SUM_SQ(3, 4)
 MOD(10, 3)
+SUM_SQ(1, 1) + MOD(5, 2)
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
