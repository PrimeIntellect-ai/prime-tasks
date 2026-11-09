#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc sed
    pip3 install pytest

    mkdir -p /home/user/asset_processor
    cd /home/user/asset_processor
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > processor.c
#include <stdio.h>
int main(int argc, char **argv) {
    if(argc < 2) return 1;
    printf("Processed: %s\n", argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > build_and_process.sh
#!/bin/bash

gcc -o processor processor.c
TARGET_DIR="$1"
find "$TARGET_DIR" -type f -name '*.txt' | while read -r file; do
    ./processor "$file"
done
EOF
    chmod +x build_and_process.sh

    git add processor.c build_and_process.sh
    git commit -m "Initial commit"
    git tag v1.0

    for i in $(seq 2 136); do
        echo "// Dummy comment $i" >> processor.c
        git commit -am "Update processor $i"
    done

    cat << 'EOF' > build_and_process.sh
#!/bin/bash

gcc -o processor processor.c
TARGET_DIR=$1
for file in $(find "$TARGET_DIR" -type f -name '*.txt'); do
    ./processor $file
done
EOF
    chmod +x build_and_process.sh
    git commit -am "Refactor loop"

    BAD_COMMIT=$(git rev-parse HEAD)
    echo "$BAD_COMMIT" > /tmp/expected_bad_commit.txt

    for i in $(seq 138 149); do
        echo "// Dummy comment $i" >> processor.c
        git commit -am "Update processor $i"
    done

    sed -i 's/#include <stdio.h>/#include <stdio.h>\n#error "Simulated compiler error"/' processor.c
    git commit -am "Accidental compiler error"

    for i in $(seq 151 154); do
        echo "// Dummy comment $i" >> processor.c
        git commit -am "Update processor $i"
    done

    sed -i '/#error "Simulated compiler error"/d' processor.c
    git commit -am "Fix compiler error"

    for i in $(seq 156 200); do
        echo "// Dummy comment $i" >> processor.c
        git commit -am "Update processor $i"
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
