#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick gawk fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/bin

    # Generate the specification sheet
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 16 -fill black \
    -draw "text 10,30 'PIPELINE SPECIFICATION DAG'" \
    -draw "text 10,60 'Step 1. Filter: Drop malformed rows.'" \
    -draw "text 10,90 'Step 2. Masking: NewID = (SensorID * 137) % 1000'" \
    -draw "text 10,120 'Step 3. Imputation: If TempB is empty, TempB = (TempA * 3) + 7'" \
    -draw "text 10,150 'Step 4. Output Template: Generate string exactly formatted as: [NewID] => {TempA, TempB}'" \
    /app/spec_sheet.png

    # Create the oracle binary (using awk wrapped in a bash script)
    cat << 'EOF' > /app/bin/oracle_cleaner
#!/bin/bash
awk -F, '
/^[0-9]+,[0-9]+,([0-9]+)?$/ {
    id=$1
    ta=$2
    tb=$3
    new_id = (id * 137) % 1000
    if (tb == "") {
        tb = (ta * 3) + 7
    }
    printf("[%d] => {%d, %d}\n", new_id, ta, tb)
}
'
EOF
    chmod +x /app/bin/oracle_cleaner

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
