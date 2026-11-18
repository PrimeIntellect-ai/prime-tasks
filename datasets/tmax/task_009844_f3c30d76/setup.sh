#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk findutils
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/data_01.csv
0.0,0.0
1.0,1.0
2.0,4.0
3.0,9.0
4.0,16.0
5.0,25.0
6.0,36.0
7.0,49.0
8.0,64.0
9.0,81.0
10.0,100.0
EOF

    cat << 'EOF' > /home/user/data/data_02.csv
0.0,10.0
2.0,8.0
4.0,6.0
6.0,4.0
8.0,2.0
10.0,0.0
EOF

    cat << 'EOF' > /home/user/data/data_03.csv
0.0,5.0
0.5,5.0
1.0,5.0
1.5,5.0
2.0,5.0
EOF

    cat << 'EOF' > /home/user/integrate.awk
BEGIN { FS=","; sum=0; first=1 }
{
    if (first) {
        t_prev=$1; y_prev=$2; first=0;
    } else {
        sum += y_prev * ($1 - t_prev);
        t_prev=$1; y_prev=$2;
    }
}
END { printf "%.6f\n", sum }
EOF

    cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash
rm -f /home/user/final_output.txt
find /home/user/data -name "*.csv" | xargs -P 4 -I {} sh -c '
    base=$(basename "{}")
    val=$(awk -f /home/user/integrate.awk "{}")
    echo "$base,$val" >> /home/user/final_output.txt
'
EOF
    chmod +x /home/user/pipeline.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data /home/user/integrate.awk /home/user/pipeline.sh
    chmod -R 777 /home/user
