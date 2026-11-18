#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user/sim
    cat << 'EOF' > /home/user/sim/integrate.sh
#!/bin/bash
T_END=${1:-2.0}
awk -v t_end="$T_END" '
BEGIN {
    t = 0.0;
    y = 1.0;
    dt = 0.1;
    tol = 0.001;
    print t, y;
    while (t < t_end) {
        # Full step
        f1 = -2 * y;
        y_full = y + dt * f1;

        # Two half steps
        y_half = y + (dt / 2.0) * f1;
        f2 = -2 * y_half;
        y_two_half = y_half + (dt / 2.0) * f2;

        # Error estimate
        err = y_full - y_two_half;
        if (err < 0) err = -err;
        if (err == 0) err = 1e-10;

        # BUG: Incorrect adaptation logic (increases step size on large error)
        dt_new = dt * (err / tol);

        if (dt_new > 0.5) dt_new = 0.5;
        if (dt_new < 0.001) dt_new = 0.001;

        if (err <= tol) {
            t = t + dt;
            y = y_two_half;
            print t, y;
        }
        dt = dt_new;
    }
}'
EOF
    chmod +x /home/user/sim/integrate.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
