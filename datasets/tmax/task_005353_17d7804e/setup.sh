#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget bzip2 gawk perl
    pip3 install pytest

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/reference_etl.sh
#!/bin/bash
awk -F',' '$1 % 10 == 0 { sum[$2]+=$3; count[$2]++ } END { for (s in sum) print s "," sum[s] "," count[s] }' | sort -t',' -k1,1
EOF
    chmod +x /opt/oracle/reference_etl.sh

    # Vendor GNU parallel and apply perturbation
    mkdir -p /app
    cd /app
    wget https://ftp.gnu.org/gnu/parallel/parallel-20231022.tar.bz2
    tar -xjf parallel-20231022.tar.bz2
    sed -i '1s/perl/pperl/' /app/parallel-20231022/src/parallel

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
