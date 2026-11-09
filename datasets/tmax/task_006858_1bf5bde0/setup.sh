#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_repo.sh
#!/bin/bash
mkdir -p /home/user/sorter_repo
cd /home/user/sorter_repo
git config --global user.email "test@example.com"
git config --global user.name "Test User"
git init

cat << 'CODE' > main.c
#include <stdio.h>
#include <stdlib.h>
extern void custom_sort(int *arr, int l, int r);

int main(int argc, char **argv) {
    if (argc < 2) return 0;
    int n = argc - 1;
    int *arr = malloc(n * sizeof(int));
    for (int i = 0; i < n; i++) {
        arr[i] = atoi(argv[i+1]);
    }
    custom_sort(arr, 0, n - 1);
    for (int i = 0; i < n; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n");
    free(arr);
    return 0;
}
CODE

cat << 'CODE' > Makefile
all:
	gcc -O0 -g main.c sort.c -o sorter
clean:
	rm -f sorter
CODE

cat << 'CODE' > test.sh
#!/bin/bash
make clean > /dev/null 2>&1
make > /dev/null 2>&1
ulimit -s 1024
timeout 1s ./sorter 5 4 3 2 1 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    exit 1
fi
exit 0
CODE
chmod +x test.sh

# Initial good sort.c
cat << 'CODE' > sort.c
#include <stdlib.h>

void merge(int *arr, int l, int m, int r) {
    int n1 = m - l + 1;
    int n2 = r - m;
    int *L = malloc(n1 * sizeof(int));
    int *R = malloc(n2 * sizeof(int));
    for(int i = 0; i < n1; i++) L[i] = arr[l + i];
    for(int j = 0; j < n2; j++) R[j] = arr[m + 1 + j];
    int i = 0, j = 0, k = l;
    while(i < n1 && j < n2) {
        if(L[i] <= R[j]) { arr[k] = L[i]; i++; }
        else { arr[k] = R[j]; j++; }
        k++;
    }
    while(i < n1) { arr[k] = L[i]; i++; k++; }
    while(j < n2) { arr[k] = R[j]; j++; k++; }
    free(L); free(R);
}

void custom_sort(int *arr, int l, int r) {
    if (l < r) {
        int m = l + (r - l) / 2;
        custom_sort(arr, l, m);
        custom_sort(arr, m + 1, r);
        merge(arr, l, m, r);
    }
}
CODE

git add main.c Makefile test.sh sort.c
git commit -m "Initial commit"

# Create 200 commits, introduce bug at commit 137
for i in {2..200}; do
    echo "// Dummy comment $i" >> sort.c
    if [ $i -eq 137 ]; then
        # Introduce the infinite recursion bug (off-by-one: m instead of m+1)
        sed -i 's/custom_sort(arr, m + 1, r);/custom_sort(arr, m, r);/' sort.c
    fi
    git add sort.c
    git commit -m "Commit $i"
done
EOF

    chmod +x /home/user/setup_repo.sh
    /home/user/setup_repo.sh

    cd /home/user/sorter_repo
    BAD_COMMIT=$(git log --oneline | grep "Commit 137" | awk '{print $1}')
    BAD_COMMIT_FULL=$(git rev-parse $BAD_COMMIT)
    echo $BAD_COMMIT_FULL > /home/user/.truth_bad_commit.txt

    chmod -R 777 /home/user
