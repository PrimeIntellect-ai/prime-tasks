#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick bc gawk
    pip3 install pytest

    mkdir -p /app

    # Create the oracle script
    cat << 'EOF' > /app/oracle_calc_pi.sh
#!/bin/bash
T_SEQ=$1
T_PAR=$2
N=$3
C_PENALTY=$4
PI=$(( (T_SEQ * 1000) / (N * T_PAR) - C_PENALTY ))
echo $PI
EOF
    chmod +x /app/oracle_calc_pi.sh

    # Generate the image fixture
    convert -background white -fill black -pointsize 24 label:"Formula for Profiling Index (integer math only):\nPI = ((T_seq * 1000) / (N * T_par)) - C_penalty" /app/spec.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
