#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip gcc make tesseract-ocr imagemagick patch
    pip3 install pytest packaging

    mkdir -p /app/patches
    mkdir -p /home/user/processor
    mkdir -p /home/user/api_tests

    # Create oracle processor
    cat << 'EOF' > /app/oracle_processor.c
#include <stdio.h>
#include <ctype.h>

int main() {
    int c;
    while ((c = getchar()) != EOF) {
        if (isalpha(c)) {
            if (c >= 'a' && c <= 'z') putchar((c - 'a' + 13) % 26 + 'a');
            else putchar((c - 'A' + 13) % 26 + 'A');
        } else if (isdigit(c)) {
            putchar((c - '0' + 5) % 10 + '0');
        } else {
            putchar(c);
        }
    }
    return 0;
}
EOF
    gcc -o /app/oracle_processor /app/oracle_processor.c
    rm /app/oracle_processor.c

    # Create buggy processor
    cat << 'EOF' > /home/user/processor/processor.c
#include <stdio.h>
#include <ctype.h>

int main() {
    int c;
    while ((c = getchar()) != EOF) {
        if (isalpha(c)) {
            if (c >= 'a' && c <= 'z') putchar((c - 'a' + 13) % 26 + 'a');
            else putchar((c - 'A' + 13) % 26 + 'A');
        } else if (isdigit(c)) {
            putchar((c - '0' + 1) % 10 + '0');
        } else {
            putchar(c);
        }
    }
    return 0;
}
EOF

    # Create Makefile with spaces
    cat << 'EOF' > /home/user/processor/Makefile
processor: processor.c
    gcc -o processor processor.c
EOF

    # Create versions.txt
    cat << 'EOF' > /home/user/versions.txt
1.0.0
1.3.5
1.4.0
1.5.0
2.0.0
EOF

    # Create api_version.png
    # ImageMagick security policy workaround for PDF/fonts might be needed, but basic label should work
    convert -pointsize 36 -background white -fill black label:"VERSION: 1.4.2" /app/api_version.png

    # Create api_tests
    cat << 'EOF' > /home/user/api_tests/module_a.py
import sys
if 'module_b' in sys.modules:
    raise ImportError("module_b cannot be imported before module_a")
def foo(): return 1
EOF

    cat << 'EOF' > /home/user/api_tests/module_b.py
pass
EOF

    cat << 'EOF' > /home/user/api_tests/test_api.py
import module_b
import module_a

def test_something():
    assert module_a.foo() == 1
EOF

    # Create patches
    cat << 'EOF' > /app/patches/fix_imports_1.4.0.patch
--- test_api.py
+++ test_api.py
@@ -1,5 +1,5 @@
-import module_b
 import module_a
+import module_b

 def test_something():
     assert module_a.foo() == 1
EOF

    cat << 'EOF' > /app/patches/fix_imports_1.5.0.patch
--- test_api.py
+++ test_api.py
@@ -1,5 +1,5 @@
-import module_b
+import module_a syntax error!
 import module_a
+import module_b

 def test_something():
     assert module_a.foo() == 1
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
