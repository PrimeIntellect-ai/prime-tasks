#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/app/lib /home/user/app/bin /home/user/data /home/user/app/src

    # Create input data
    cat << 'EOF' > /home/user/data/input.txt
START_RECORD
APP nginx
VERSION 1.21.0
END_RECORD
START_RECORD
APP redis
VERSION 6.2.5
END_RECORD
START_RECORD
APP python
VERSION 3.9.7
END_RECORD
EOF

    # Create C source for shared library
    cat << 'EOF' > /home/user/app/src/libsemver.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int check_version(const char* version) {
    if (strchr(version, '.') != NULL) {
        return 1;
    }
    return 0;
}
EOF

    # Create C source for binary
    cat << 'EOF' > /home/user/app/src/vercheck.c
#include <stdio.h>
extern int check_version(const char* version);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    if (check_version(argv[1])) {
        printf("VALID\n");
        return 0;
    }
    printf("INVALID\n");
    return 1;
}
EOF

    # Compile shared lib
    gcc -shared -fPIC -Wl,-soname,libsemver.so.1 -o /home/user/app/lib/libsemver.so.1.0 /home/user/app/src/libsemver.c

    # Symlink to compile binary, then remove it to break runtime
    ln -s /home/user/app/lib/libsemver.so.1.0 /home/user/app/lib/libsemver.so
    gcc -o /home/user/app/bin/vercheck /home/user/app/src/vercheck.c -L/home/user/app/lib -lsemver
    rm /home/user/app/lib/libsemver.so

    # Create Bash modules with circular dependency
    cat << 'EOF' > /home/user/app/lib/module_a.sh
#!/bin/bash
source /home/user/app/lib/module_b.sh

process_data() {
    local input_file=$1
    echo "["
    local first=1
    local in_record=0
    local app=""
    local version=""

    while IFS= read -r line; do
        if [[ "$line" == "START_RECORD" ]]; then
            in_record=1
            app=""
            version=""
        elif [[ "$line" == "END_RECORD" ]]; then
            in_record=0
            # Call from module_b
            if validate_ver "$version"; then
                if [ $first -eq 0 ]; then echo ","; fi
                echo -n "  {\"app\": \"$app\", \"version\": \"$version\"}"
                first=0
            fi
        elif [[ $in_record -eq 1 ]]; then
            if [[ "$line" == APP* ]]; then
                app="${line#APP }"
            elif [[ "$line" == VERSION* ]]; then
                version="${line#VERSION }"
            fi
        fi
    done < "$input_file"
    echo ""
    echo "]"
}
EOF

    cat << 'EOF' > /home/user/app/lib/module_b.sh
#!/bin/bash
# CIRCULAR DEPENDENCY HERE
source /home/user/app/lib/module_a.sh

validate_ver() {
    local ver=$1
    # Needs LD_LIBRARY_PATH to run vercheck properly
    local res=$(/home/user/app/bin/vercheck "$ver" 2>/dev/null)
    if [[ "$res" == "VALID" ]]; then
        return 0
    else
        return 1
    fi
}
EOF

    # Create run script
    cat << 'EOF' > /home/user/app/run.sh
#!/bin/bash
export LD_LIBRARY_PATH=/home/user/app/lib:$LD_LIBRARY_PATH
source /home/user/app/lib/module_a.sh
process_data /home/user/data/input.txt > /home/user/processed_data.json
EOF

    chmod +x /home/user/app/run.sh
    chmod +x /home/user/app/bin/vercheck

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
