#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gawk
    pip3 install pytest

    mkdir -p /app

    # Create the settings image
    convert -background white -fill black -pointsize 24 label:"GRAPH NORMALIZATION CONFIG\n==========================\nlambda = 12\nEnsure this is applied to the diagonal." /app/settings.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle_normalize.sh
#!/bin/bash
awk -v lambda=12 '
{
    for(i=1; i<=NF; i++) {
        a[NR,i] = $i
        rowsum[NR] += $i
    }
    cols = NF
}
END {
    for(i=1; i<=NR; i++) {
        for(j=1; j<=cols; j++) {
            if (i==j) {
                val = rowsum[i] - a[i,j] + lambda
            } else {
                val = -a[i,j]
            }
            printf "%s%s", val, (j==cols ? "" : " ")
        }
        print ""
    }
}'
EOF
    chmod +x /app/oracle_normalize.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
