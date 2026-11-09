#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/data
    mkdir -p /home/user/project/include

    cat << 'EOF' > /home/user/project/src/generator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double find_sqrt(double n) {
    double x = n / 2.0;
    if (n == 0) return 0;

    for (int i = 0; i < 100; i++) {
        double f = x * x - n;
        if (fabs(f) < 1e-5) return x;

        // BUG: Incorrect derivative for f(x) = x^2 - n
        // Should be: double df = 2.0 * x;
        double df = 2.0; 

        x = x - f / df;
    }

    fprintf(stderr, "Convergence failure for input: %.1f\n", n);
    exit(1);
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    double n = atof(argv[1]);
    double res = find_sqrt(n);
    printf("#define SQRT_%d %f\n", (int)n, res);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/src/main.c
#include <stdio.h>
#include "tables.h"

int main() {
    printf("Application initialized successfully.\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/data/inputs.txt
4.0
16.0
25.0
64.0
EOF

    cat << 'EOF' > /home/user/project/generate.sh
#!/bin/bash
mkdir -p include
echo "// Generated tables" > include/tables.h
# Emulate the interleaved parallel build log
cat << 'LOG' > build.log
[PID 101] Start processing 4.0
[PID 102] Start processing 16.0
[PID 103] Start processing 25.0
[PID 101] Finished processing 4.0
[PID 104] Start processing 64.0
Convergence failure for input: 16.0
[PID 102] Generator crashed!
[PID 103] Finished processing 25.0
[PID 104] Finished processing 64.0
make: *** [Makefile:12: tables] Error 1
LOG
exit 1
EOF

    chmod +x /home/user/project/generate.sh

    cat << 'EOF' > /home/user/project/Makefile
CC=gcc
CFLAGS=-I./include -lm

all: app

generator: src/generator.c
	$(CC) src/generator.c -o generator $(CFLAGS)

tables: generator
	# In a real run, this would be: cat data/inputs.txt | xargs -P 4 ...
	# We are hardcoding the script that contains the failed log state for the task
	bash ./generate.sh || exit 1

app: tables src/main.c
	$(CC) src/main.c -o app $(CFLAGS)

clean:
	rm -f generator app include/tables.h build.log
EOF

    # Generate the initial failed log file
    cd /home/user/project && ./generate.sh || true

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
