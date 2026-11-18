#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/math_proj/lib
    mkdir -p /home/user/math_proj/logs

    cat << 'EOF' > /home/user/math_proj/logs/build.log
Traceback (Bash execution):
  File "./run_analysis.sh", line 3, in main
  File "./lib/math_v1.sh", line 2: syntax error: unexpected end of file
Error: Failed to load math dependencies. Conflicting library versions detected.
EOF

    cat << 'EOF' > /home/user/math_proj/lib/math_v1.sh
# Corrupt legacy math library
function collatz() {
    echo "ERROR
EOF

    cat << 'EOF' > /home/user/math_proj/lib/math_v2.sh
# V2 Math Library
collatz() {
    local n=$1
    local steps=0
    while [ $n -ne 1 ]; do
        if [ $(expr $n % 2) -eq 0 ]; then
            n=$(expr $n / 2)
        else
            n=$(expr 3 \* $n + 1)
        fi
        steps=$(expr $steps + 1)
    done
    echo $steps
}
EOF

    cat << 'EOF' > /home/user/math_proj/run_analysis.sh
#!/bin/bash
source ./lib/math_v1.sh
source ./lib/math_v2.sh

max_len=0
max_num=0

for i in $(seq 1 500); do
    len=$(collatz $i)
    if [ "$len" -gt "$max_len" ]; then
        max_len=$len
        max_num=$i
    fi
done
echo "Max Length: $max_len, Number: $max_num" > /home/user/math_proj/result.txt
EOF

    chmod +x /home/user/math_proj/run_analysis.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
