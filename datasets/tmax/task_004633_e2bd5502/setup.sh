#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk sed bc curl redis-server
pip3 install pytest

mkdir -p /app/signals
cat << 'EOF' > /app/signals/test1
>Signal_test1
0.0 1.0
1.0 2.0
2.0 3.0
EOF

cat << 'EOF' > /app/oracle_compute.sh
#!/bin/bash
awk '
/^>/ { next }
NF == 2 {
    t = $1; y = $2;
    if (NR > 2) {
        area += (t - prev_t) * (y + prev_y) / 2.0;
    }
    prev_t = t; prev_y = y;
}
END {
    printf "%.4f\n", area;
}' "$1"
EOF
chmod +x /app/oracle_compute.sh

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/compute_integral.sh
#!/bin/bash
# Buggy implementation: constant step size
step=1.0
area=0
awk -v step="$step" '
/^>/ { next }
NF == 2 {
    y = $2;
    if (NR > 2) {
        area += step * (y + prev_y) / 2.0;
    }
    prev_y = y;
}
END {
    printf "%.4f\n", area;
}' "$1"
EOF
chmod +x /home/user/compute_integral.sh

chmod -R 777 /home/user
chmod -R 777 /app
