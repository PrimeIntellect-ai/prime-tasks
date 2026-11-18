#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc strace
    pip3 install pytest

    mkdir -p /home/user/sim_project/src /home/user/sim_project/bin

    cat << 'EOF' > /home/user/sim_project/src/math_helper.c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <math.h>

int main() {
    int fd = open("/home/user/sim_project/data/input.dat", O_RDONLY);
    if (fd < 0) {
        return 1; // Fails silently as stderr is suppressed by wrapper
    }
    char buf[32] = {0};
    read(fd, buf, 31);
    close(fd);

    double val = atof(buf);
    // Dummy math operation to force linker error if math lib is missing
    double dummy = sqrt(val); 

    printf("%f\n", val);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/sim_project/build.sh
#!/bin/bash
# Bug: Missing math lib flag at the end of the compilation command
gcc -O2 -o /home/user/sim_project/bin/helper /home/user/sim_project/src/math_helper.c
EOF

    cat << 'EOF' > /home/user/sim_project/simulate.sh
#!/bin/bash

# Ensure bin exists
if [ ! -f "/home/user/sim_project/bin/helper" ]; then
    echo "Helper binary not found. Run build.sh first."
    exit 1
fi

# Run helper, suppressing errors
val=$(/home/user/sim_project/bin/helper 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Helper failed to read input."
    exit 1
fi

curr=$val
next=0
threshold="0.0000000001"

for i in {1..100}; do
    # Bug: bc defaults to 0 scale (integer math). This loses precision and prevents convergence.
    # Fix: next=$(echo "scale=10; ($curr + $val / $curr) / 2" | bc)
    next=$(echo "($curr + $val / $curr) / 2" | bc)

    diff=$(echo "scale=10; $curr - $next" | bc | tr -d '-')
    is_converged=$(echo "$diff < $threshold" | bc)

    if [ "$is_converged" -eq 1 ]; then
        echo "$next" > /home/user/sim_project/output_result.txt
        echo "Converged!"
        exit 0
    fi
    curr=$next
done

echo "Failed to converge."
exit 1
EOF

    chmod +x /home/user/sim_project/build.sh /home/user/sim_project/simulate.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
