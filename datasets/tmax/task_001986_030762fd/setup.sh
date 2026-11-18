#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make git binutils
pip3 install pytest

mkdir -p /home/user/stats_project/lib
cd /home/user/stats_project

# Create the math libraries
cat << 'EOF' > legacy.c
double compute_mean(double *arr, int n) {
    double sum = 0;
    for(int i = 0; i < n; i++) sum += arr[i];
    return sum / n;
}
EOF

cat << 'EOF' > advanced.c
double compute_mean(double *arr, int n) {
    double sum = 0;
    double c = 0;
    for(int i = 0; i < n; i++) {
        double y = arr[i] - c;
        double t = sum + y;
        c = (t - sum) - y;
        sum = t;
    }
    return sum / n;
}
EOF

gcc -c legacy.c -o legacy.o
gcc -c advanced.c -o advanced.o
ar rcs lib/liblegacy.a legacy.o
ar rcs lib/libadvanced.a advanced.o
rm legacy.c advanced.c legacy.o advanced.o

# Create the main program
cat << 'EOF' > calc_variance.c
#include <stdio.h>
#include <stdlib.h>
#include "stats.h"

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    double data[1000];
    int n = 0;
    while(fscanf(f, "%lf", &data[n]) == 1) n++;
    fclose(f);

    if (n == 0) return 1;

    double mean = compute_mean(data, n);
    double var = 0;
    for(int i=0; i<n; i++) {
        var += (data[i] - mean) * (data[i] - mean);
    }
    var /= n;
    printf("%.4f\n", var);
    return 0;
}
EOF

# Create the missing header
cat << 'EOF' > stats.h
#ifndef STATS_H
#define STATS_H
double compute_mean(double *arr, int n);
#endif
EOF

# Create the broken Makefile
cat << 'EOF' > Makefile
calc_variance: calc_variance.c
	gcc -O2 -o calc_variance calc_variance.c -L./lib -ladvanced -llegacy -lm
EOF

# Create the dataset
cat << 'EOF' > dataset.txt
10.0 12.0 14.0 16.0 18.0
EOF

# Initialize git and make initial commit
git init
git config user.email "junior@example.com"
git config user.name "Junior Dev"
git add lib/liblegacy.a lib/libadvanced.a calc_variance.c stats.h Makefile dataset.txt
git commit -m "Initial commit of variance calculator"

# Create the cleanup script that breaks on spaces
cat << 'EOF' > cleanup.sh
#!/bin/bash
# Bad script that doesn't quote variables
for f in $(cat trash.txt); do
    rm -f $f
done
EOF
chmod +x cleanup.sh

# Create the trash list with a space in a filename
cat << 'EOF' > trash.txt
old backup.txt
stats.h
EOF

# Run the bad script and commit the damage
./cleanup.sh
git rm stats.h
git commit -m "Cleanup old files"

rm cleanup.sh trash.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
