#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git build-essential
pip3 install pytest

mkdir -p /home/user/corpora/clean
mkdir -p /home/user/corpora/evil
mkdir -p /app/vendor

git clone --branch 3.4.0 --depth 1 https://gitlab.com/libeigen/eigen.git /app/vendor/eigen

sed -i 's/using std::isnan;/#error "Deliberate perturbation: std::isnan disabled"\nusing std::isnan;/g' /app/vendor/eigen/Eigen/src/Core/MathFunctions.h

cat << 'EOF' > /home/user/corpora/clean/embed1.txt
0.1 0.2 -0.5 0.3 0.0 1.2
EOF
cat << 'EOF' > /home/user/corpora/clean/embed2.txt
5.0 5.0 -5.0 5.0
EOF

cat << 'EOF' > /home/user/corpora/evil/embed_nan.txt
0.1 0.2 NaN 0.3 0.0 1.2
EOF

cat << 'EOF' > /home/user/corpora/evil/embed_outlier.txt
40.0 30.0 10.0 5.0
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app/vendor
