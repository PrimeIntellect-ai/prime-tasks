#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/data
    cd /home/user/project

    # Create data files with spaces in names
    cat << 'EOF' > "data/dataset 1.txt"
10.0
20.0
30.0
40.0
50.0
EOF

    cat << 'EOF' > "data/dataset 2.txt"
15.0
25.0
35.0
45.0
55.0
EOF

    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # COMMIT 1: Initial working, single-threaded version
    cat << 'EOF' > solver.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define MAX_ITER 10000

double *data;
int data_size;

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    data = malloc(1000 * sizeof(double));
    data_size = 0;
    while(fscanf(f, "%lf", &data[data_size]) == 1) {
        data_size++;
    }
    fclose(f);

    double sum = 0.0;
    for (int i = 0; i < data_size; i++) {
        double n = data[i];
        double x = n;
        int iter = 0;
        while(iter < MAX_ITER) {
            double delta = (x * x - n) / (2 * x);
            if (fabs(delta) < 1e-5) break;
            x = x - delta;
            iter++;
        }
        if (iter == MAX_ITER) {
            printf("Failed to converge for %f\n", n);
        }
        sum += x;
    }
    printf("File: %s | Sum of roots: %.4f\n", argv[1], sum);
    free(data);
    return 0;
}
EOF
    gcc -O2 -pthread solver.c -o solver -lm
    git add solver.c data/
    git commit -m "Initial commit: working single-threaded solver"

    # COMMIT 2: Add buggy shell script
    cat << 'EOF' > run_pipeline.sh
#!/bin/bash
for f in $(ls data/); do
    ./solver "data/$f"
done
EOF
    chmod +x run_pipeline.sh
    git add run_pipeline.sh
    git commit -m "Add pipeline runner script"

    # COMMIT 3: Introduce multithreading AND the global delta race condition (THE BAD COMMIT)
    cat << 'EOF' > solver.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <pthread.h>

#define MAX_ITER 10000
#define NUM_THREADS 4

double *data;
int data_size;
double delta; // BUG: Global delta causes race condition across threads

void* worker(void* arg) {
    int tid = *(int*)arg;
    int chunk = (data_size + NUM_THREADS - 1) / NUM_THREADS;
    int start = tid * chunk;
    int end = start + chunk;
    if (end > data_size) end = data_size;

    for (int i = start; i < end; i++) {
        double n = data[i];
        double x = n;
        int iter = 0;
        while(iter < MAX_ITER) {
            delta = (x * x - n) / (2 * x);
            if (fabs(delta) < 1e-5) break;
            x = x - delta;
            iter++;
        }
        if (iter == MAX_ITER) {
            printf("Failed to converge for %f\n", n);
        }
        data[i] = x;
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    data = malloc(1000 * sizeof(double));
    data_size = 0;
    while(fscanf(f, "%lf", &data[data_size]) == 1) {
        data_size++;
    }
    fclose(f);

    pthread_t threads[NUM_THREADS];
    int tids[NUM_THREADS];
    for (int i = 0; i < NUM_THREADS; i++) {
        tids[i] = i;
        pthread_create(&threads[i], NULL, worker, &tids[i]);
    }

    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    double sum = 0.0;
    for (int i = 0; i < data_size; i++) {
        sum += data[i];
    }
    printf("File: %s | Sum of roots: %.4f\n", argv[1], sum);
    free(data);
    return 0;
}
EOF
    git add solver.c
    git commit -m "Optimize solver with pthreads"

    # COMMIT 4: Unrelated update
    echo "Test update" > README.md
    git add README.md
    git commit -m "Update README"

    chmod -R 777 /home/user
