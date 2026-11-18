#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat netcat-openbsd jq cron gawk
    pip3 install pytest

    mkdir -p /app/bash-jaccard-logger-1.0
    cat << 'EOF' > /app/bash-jaccard-logger-1.0/process_log.sh
#!/bin/bash
# process_log.sh
# Usage: process_log.sh "string1" "string2"

str1="$1"
str2="$2"

# PERTURBATION: Broken unicode handling
str1=$(echo "$str1" | sed 's/\\u/broken_unicode/g')
str2=$(echo "$str2" | sed 's/\\u/broken_unicode/g')

# Normalization
str1=$(echo "$str1" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')
str2=$(echo "$str2" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')

# Jaccard
read -a words1 <<< "$str1"
read -a words2 <<< "$str2"

declare -A set1
declare -A set2

for w in "${words1[@]}"; do set1["$w"]=1; done
for w in "${words2[@]}"; do set2["$w"]=1; done

intersection=0
for w in "${!set1[@]}"; do
    if [[ -n "${set2[$w]}" ]]; then
        intersection=$((intersection + 1))
    fi
done

union=0
declare -A union_set
for w in "${words1[@]}"; do union_set["$w"]=1; done
for w in "${words2[@]}"; do union_set["$w"]=1; done
union=${#union_set[@]}

if [ $union -eq 0 ]; then
    echo "1.00"
else
    awk -v i="$intersection" -v u="$union" 'BEGIN { printf "%.2f\n", i/u }'
fi
EOF
    chmod +x /app/bash-jaccard-logger-1.0/process_log.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
