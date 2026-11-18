#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick gawk
    pip3 install pytest

    mkdir -p /app /home/user

    # Create the image with the ground truth
    convert -background white -fill black -pointsize 18 label:"CRITICAL PARAMETER UPDATE:\nThe required tolerance for the model fit is TOL=0.00042\nEnsure all models use this tolerance." /app/params.png

    # Create the buggy Bash/Awk script
    cat << 'EOF' > /home/user/adaptive_integrator.sh
#!/bin/bash
y0=$1
t_end=$2
h=$3

awk -v y="$y0" -v t="0" -v t_end="$t_end" -v h="$h" '
function f(y, t) {
    return -y*y + t
}
BEGIN {
    steps = 0
    while (t < t_end) {
        if (t + h > t_end) {
            h = t_end - t
        }

        # Euler full step
        y_full = y + h * f(y, t)

        # Two half steps
        h_half = h / 2.0
        y_half = y + h_half * f(y, t)
        y_half = y_half + h_half * f(y_half, t + h_half)

        # Error estimate
        err = y_full - y_half
        if (err < 0) err = -err

        # BROKEN ADAPTATION
        h_new = h * 1.5 

        if (err <= 0.001) {
            y = y_half
            t = t + h
            steps++
        }
        h = h_new
    }
    printf "%.5f %d\n", y, steps
}'
EOF
    chmod +x /home/user/adaptive_integrator.sh

    # Create the oracle program in Python (which acts as the reference)
    cat << 'EOF' > /app/oracle.py
import sys, math

y = float(sys.argv[1])
t_end = float(sys.argv[2])
h = float(sys.argv[3])
t = 0.0
steps = 0
TOL = 0.00042

def f(y, t):
    return -y*y + t

while t < t_end:
    # floating point precision guard
    if t + h > t_end or abs(t + h - t_end) < 1e-9:
        h = t_end - t
        if h <= 0:
            break

    y_full = y + h * f(y, t)
    h_half = h / 2.0
    y_half1 = y + h_half * f(y, t)
    y_half = y_half1 + h_half * f(y_half1, t + h_half)

    err = abs(y_full - y_half)

    # Avoid division by zero
    if err == 0:
        err = 1e-12

    h_new = h * 0.9 * math.sqrt(TOL / err)

    if h_new > 0.5: h_new = 0.5
    if h_new < 1e-5: h_new = 1e-5

    if err <= TOL:
        y = y_half
        t = t + h
        steps += 1

    h = h_new

print(f"{y:.5f} {steps}")
EOF

    cat << 'EOF' > /app/oracle_integrator
#!/bin/bash
python3 /app/oracle.py "$1" "$2" "$3"
EOF
    chmod +x /app/oracle_integrator

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
