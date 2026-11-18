#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace
    pip3 install pytest

    mkdir -p /home/user/bin
    mkdir -p /home/user/suspicious_data

    cat << 'EOF' > /home/user/bin/data_extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char buf[16] = {0};
    size_t bytes = fread(buf, 1, sizeof(buf), f);
    fclose(f);

    if (bytes >= 4 && strncmp(buf, "DEAD", 4) == 0) {
        fprintf(stderr, "thread 'main' panicked at 'called `Result::unwrap()` on an `Err` value: ParseError'\n");
        abort();
    }

    char out_name[512];
    snprintf(out_name, sizeof(out_name), "%s.out", argv[1]);
    FILE *out = fopen(out_name, "w");
    if(out) {
        fprintf(out, "extracted_payload_data\n");
        fclose(out);
    }
    return 0;
}
EOF

    gcc -o /home/user/bin/data_extractor /home/user/bin/data_extractor.c
    rm /home/user/bin/data_extractor.c

    for i in $(seq -w 1 50); do
        echo "VALID_DATA_$i" > /home/user/suspicious_data/payload_$i.dat
    done

    echo "DEADBEEF" > /home/user/suspicious_data/payload_37.dat

    cat << 'EOF' > /home/user/analyze.sh
#!/bin/bash
cd /home/user/suspicious_data

# Keep processing as long as there are .dat files
# BUG: _extracted.dat matches *.dat, so this loop never ends if it creates new .dat files.
while ls *.dat >/dev/null 2>&1; do
    for file in *.dat; do
        if [[ "$file" == *"_extracted.dat" ]]; then
            # We skip processing but the while loop condition is still met!
            continue
        fi

        /home/user/bin/data_extractor "$file" >/dev/null 2>&1

        if [ -f "${file}.out" ]; then
            mv "${file}.out" "${file}_extracted.dat"
            # Remove original to avoid reprocessing
            rm "$file"
        fi
    done
done
EOF
    chmod +x /home/user/analyze.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
