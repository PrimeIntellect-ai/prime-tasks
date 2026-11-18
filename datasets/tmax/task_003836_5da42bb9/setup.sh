#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

mkdir -p /app

espeak -w /app/memo.wav "To filter the spectral sequence, apply a moving average with a window size of 3. For each element at index i, sum the elements at i minus 1, i, and i plus 1. At the boundaries, only sum the available elements, meaning two elements instead of three. Divide the sum by the number of elements in the window using integer division. Finally, subtract 10 from every smoothed value to remove the baseline noise. If any resulting value is less than zero, clip it to exactly zero. Output the numbers separated by spaces."

cat << 'EOF' > /app/oracle_filter
#!/bin/bash
args=("$@")
len=${#args[@]}
out=()
for ((i=0; i<len; i++)); do
    sum=0
    count=0
    if (( i > 0 )); then
        ((sum += args[i-1]))
        ((count++))
    fi
    ((sum += args[i]))
    ((count++))
    if (( i < len - 1 )); then
        ((sum += args[i+1]))
        ((count++))
    fi
    val=$(( sum / count ))
    ((val -= 10))
    if (( val < 0 )); then
        val=0
    fi
    out+=($val)
done
echo "${out[@]}"
EOF
chmod +x /app/oracle_filter

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
