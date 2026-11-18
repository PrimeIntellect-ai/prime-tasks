#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make git
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create sample data
    cat << 'EOF' > /home/user/sample_data.csv
1.0,2.1
2.0,3.9
3.0,6.1
4.0,8.2
5.0,10.0
EOF

    # Create secret test data
    cat << 'EOF' > /app/secret_test_data.csv
1.5,3.2
2.5,5.1
3.5,7.0
4.5,8.9
5.5,11.1
EOF

    # Initialize git repo
    mkdir -p /home/user/optimization_engine
    cd /home/user/optimization_engine
    git init
    git config user.name "Author"
    git config user.email "author@example.com"

    # Commit 0 (v1.0-good)
    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    double x[1000], y[1000];
    int n = 0;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "%lf,%lf", &x[n], &y[n]) == 2) n++;
    }
    fclose(f);

    double m = 0.0, c = 0.0;
    double lr = 0.01;
    for (int iter = 0; iter < 1000; iter++) {
        double grad_m = 0.0, grad_c = 0.0;
        double loss = 0.0;
        for (int i = 0; i < n; i++) {
            double pred = m * x[i] + c;
            double err = pred - y[i];
            grad_m += err * x[i];
            grad_c += err;
            loss += err * err;
        }
        grad_m = (2.0 / n) * grad_m;
        grad_c = (2.0 / n) * grad_c;
        loss /= n;

        // Dummy pow to require -lm
        double dummy = pow(loss, 1.0);

        m -= lr * grad_m;
        c -= lr * grad_c;
        if ((iter + 1) % 100 == 0) lr *= 0.99;
    }

    double final_loss = 0.0;
    for (int i = 0; i < n; i++) {
        double err = (m * x[i] + c) - y[i];
        final_loss += err * err;
    }
    final_loss /= n;
    printf("Final loss: %.6f\n", final_loss);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
engine: main.c
	gcc -o engine main.c -lm
EOF

    # Compile the oracle binary from the correct version
    gcc -o /app/oracle_bin main.c -lm
    strip /app/oracle_bin

    git add main.c Makefile
    git commit -m "Initial commit"
    git tag v1.0-good

    # Generate commits
    for i in $(seq 1 200); do
        if [ $i -eq 50 ]; then
            sed -i 's/-lm//' Makefile
            git add Makefile
            git commit -m "Update Makefile"
        elif [ $i -eq 120 ]; then
            sed -i 's/m -= lr \* grad_m;/m += lr \* grad_m;/' main.c
            sed -i 's/if ((iter + 1) % 100 == 0) lr \*= 0.99;//' main.c
            git add main.c
            git commit -m "Optimize gradient step"
        elif [ $i -eq 150 ]; then
            sed -i 's/gcc -o engine main.c/gcc -o engine main.c -lm/' Makefile
            git add Makefile
            git commit -m "Fix Makefile"
        else
            echo "// Refactor $i" >> main.c
            git add main.c
            git commit -m "Refactor $i"
        fi
    done

    # Ensure correct branch
    git branch -M master

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
