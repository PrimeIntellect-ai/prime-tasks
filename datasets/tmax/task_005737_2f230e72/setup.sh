#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make valgrind patch
    pip3 install pytest

    mkdir -p /home/user/release

    cat << 'EOF' > /home/user/release/data.csv
10
20
30
14
16
EOF

    cat << 'EOF' > /home/user/release/filter.cpp
extern "C" {
    int filter_value(int val) {
        return val > 15 ? val : 0;
    }
}
EOF

    cat << 'EOF' > /home/user/release/main.c
#include <stdio.h>
#include <stdlib.h>

extern int filter_value(int val);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;

    int sum = 0;
    char buf[256];
    while (fgets(buf, sizeof(buf), f)) {
        int val = atoi(buf);
        sum += filter_value(val);
    }

    printf("Sum: %d\n", sum);
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/release/large_line_support.patch
--- main.c
+++ main.c
@@ -9,10 +9,11 @@
     if (!f) return 1;

     int sum = 0;
-    char buf[256];
-    while (fgets(buf, sizeof(buf), f)) {
-        int val = atoi(buf);
+    char* line = NULL;
+    size_t len = 0;
+    while (getline(&line, &len, f) != -1) {
+        int val = atoi(line);
         sum += filter_value(val);
     }

EOF

    cat << 'EOF' > /home/user/release/Makefile
data_processor: main.o filter.o
	gcc -o data_processor main.o filter.o -lstdc++

main.o: main.c
	gcc -c main.c -g

filter.o: filter.cpp
	g++ -c filter.cpp -g

clean:
	rm -f *.o data_processor
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
