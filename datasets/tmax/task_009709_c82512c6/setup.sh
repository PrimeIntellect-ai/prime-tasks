#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git
    pip3 install pytest

    mkdir -p /home/user/decoder_project/inputs
    cd /home/user/decoder_project

    cat << 'EOF' > decoder.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    if (strcmp(argv[1], "N0vA_s3cR3t_99xY") != 0) {
        return 2;
    }

    FILE *f = fopen(argv[2], "r");
    if (!f) return 3;

    char buf[256];
    if (fgets(buf, sizeof(buf), f) != NULL) {
        // Remove trailing newline
        buf[strcspn(buf, "\n")] = 0;

        if (strstr(buf, "CORRUPT") != NULL) {
            fprintf(stderr, "thread 'main' panicked at 'called `Result::unwrap()` on an `Err` value'\n");
            abort();
        }

        printf("Decoded: %s\n", buf);
    }
    fclose(f);
    return 0;
}
EOF
    gcc decoder.c -o decoder.bin
    rm decoder.c

    for i in $(seq 1 100); do
        if [ $i -eq 42 ] || [ $i -eq 73 ]; then
            echo "DATA_CORRUPT_PAYLOAD_$i" > inputs/data_$i.txt
        else
            echo "VALID_DATA_PAYLOAD_$i" > inputs/data_$i.txt
        fi
    done

    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > analyze.py
import os
import subprocess
import glob

results = []

def process_file(filepath):
    try:
        res = subprocess.run(["./decoder.bin", "N0vA_s3cR3t_99xY", filepath], capture_output=True, text=True)
        if res.returncode == 0:
            results.append(res.stdout.strip())
    except Exception:
        pass

def main():
    files = glob.glob("inputs/*.txt")
    for f in files:
        process_file(f)
    print(f"Processed {len(results)} files.")

if __name__ == "__main__":
    main()
EOF
    git add analyze.py decoder.bin inputs/
    git commit -m "Initial working sequential version"

    echo "# logging enabled" >> analyze.py
    git commit -am "Add logging comments"

    cat << 'EOF' > analyze.py
import os
import subprocess
import glob
import threading

results = []

def process_file(filepath):
    try:
        res = subprocess.run(["./decoder.bin", "N0vA_s3cR3t_99xY", filepath], capture_output=True, text=True)
        if res.returncode == 0:
            # Race condition here
            results.append(res.stdout.strip())
    except Exception:
        pass

def main():
    files = glob.glob("inputs/*.txt")
    threads = []
    for f in files:
        t = threading.Thread(target=process_file, args=(f,))
        threads.append(t)
        t.start()
    for t in threads:
        t.join()
    print(f"Processed {len(results)} files.")

if __name__ == "__main__":
    main()
EOF
    git commit -am "Optimize by adding multithreading"
    BAD_COMMIT=$(git rev-parse HEAD)

    echo "# end of file" >> analyze.py
    git commit -am "Minor formatting"

    echo $BAD_COMMIT > /tmp/expected_bad_commit.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/decoder_project
    chmod -R 777 /home/user
