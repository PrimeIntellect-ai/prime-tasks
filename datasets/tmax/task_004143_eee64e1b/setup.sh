#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sox gawk
    pip3 install pytest

    # Create the audio file
    mkdir -p /app
    sox -n -r 44100 -c 1 /app/fan_profile.wav synth 3.5 sine 300

    # Create the oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/tv_distance_oracle.sh
#!/bin/bash
awk -v arg1="$1" -v arg2="$2" '
BEGIN {
    split(arg1, a1, ",");
    split(arg2, a2, ",");
    sum1 = 0; sum2 = 0;
    for (i in a1) sum1 += a1[i];
    for (i in a2) sum2 += a2[i];
    if (sum1 == 0 || sum2 == 0) {
        print "Invalid input";
        exit 1;
    }
    tv = 0;
    for (i in a1) {
        p = a1[i] / sum1;
        q = a2[i] / sum2;
        diff = p - q;
        if (diff < 0) diff = -diff;
        tv += diff;
    }
    printf "%.4f\n", tv / 2;
}'
EOF
    chmod +x /opt/oracle/tv_distance_oracle.sh

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
