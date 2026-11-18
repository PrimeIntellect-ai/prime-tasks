#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk make coreutils
    pip3 install pytest

    mkdir -p /app/awk-stat-1.1/src /app/awk-stat-1.1/bin
    cat << 'EOF' > /app/awk-stat-1.1/src/header.awk
#!/usr/bin/awk -f
BEGIN { FS=","; OFS="," }
NR==1 { for(i=1;i<=NF;i++) colname[i]=$i; next }
EOF

    cat << 'EOF' > /app/awk-stat-1.1/src/core.awk
{
    for(i=1;i<=NF;i++) {
        if ($i ~ /^[0-9.]+$/ && colname[i] ~ /^F/) {
            val[i,NR] = $i
            sum[i] += $i
            count[i]++
        }
    }
}
END {
    for(i=1;i<=NF;i++) {
        if (count[i] > 1) {
            mean = sum[i]/count[i]
            sq_diff_sum = 0
            for(j=2;j<=NR;j++) {
                if ((i,j) in val) {
                    sq_diff_sum += (val[i,j] - mean)^2
                }
            }
            variance = sq_diff_sum / (count[i]-1)
            print colname[i], variance
        }
    }
}
EOF

    cat << 'EOF' > /app/awk-stat-1.1/Makefile
all:
	cat src/header.awk src/missing_file.awk > bin/awk-stat
	chmod +x bin/awk-stat
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/reference_pipeline.sh
#!/bin/bash
INPUT=$1
VARS=$(/app/awk-stat-1.1/bin/awk-stat "$INPUT" | sort -k2,2nr -k1,1 | head -n 2 | awk '{print $1}')
COL_IDXS=""
HEADER=$(head -n 1 "$INPUT")
IFS=',' read -r -a HEADERS <<< "$HEADER"
KEEP_IDX=()
KEEP_IDX+=("1") # ID
KEEP_IDX+=("2") # Label

for var in $VARS; do
    for i in "${!HEADERS[@]}"; do
        if [[ "${HEADERS[$i]}" == "$var" ]]; then
            idx=$((i+1))
            KEEP_IDX+=("$idx")
        fi
    done
done

# sort the indices to maintain original relative order
IFS=$'\n' SORTED_IDX=($(sort -n <<<"${KEEP_IDX[*]}"))
unset IFS
CUT_ARGS=$(IFS=,; echo "${SORTED_IDX[*]}")

head -n 1 "$INPUT" | cut -d',' -f"$CUT_ARGS"
tail -n +2 "$INPUT" | sort -t',' -k1,1n | cut -d',' -f"$CUT_ARGS"
EOF
    chmod +x /opt/oracle/reference_pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
