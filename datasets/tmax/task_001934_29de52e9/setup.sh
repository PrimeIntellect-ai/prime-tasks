#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'SETUP_EOF' > /tmp/setup.sh
#!/bin/bash

mkdir -p /home/user/perf_math
cd /home/user/perf_math
git init -b main
git config user.email "test@example.com"
git config user.name "Test User"

# Create the calc_stats.sh script
cat << 'EOF' > calc_stats.sh
#!/bin/bash
# Calculate integer variance
input_file=$1
sum=0
count=0
while read -r num; do
    # Skip empty lines
    [ -z "$num" ] && continue
    sum=$((sum + num))
    count=$((count + 1))
done < "$input_file"

mean=$((sum / count))

sum_sq_diff=0
while read -r num; do
    [ -z "$num" ] && continue
    diff=$((num - mean))
    sq_diff=$((diff * diff))
    sum_sq_diff=$((sum_sq_diff + sq_diff))
done < "$input_file"

# The hidden fuzzing bug: if count is 1, count-1 is 0.
# Also, if all numbers are identical, variance is 0, but wait, the divide by zero
# happens if count <= 1. Let's make a specific bug:
# It normalizes by (max - min). If all numbers are the same, max-min=0.
max=$(sort -n "$input_file" | tail -n1)
min=$(sort -n "$input_file" | head -n1)
range=$((max - min))
normalized_variance=$((sum_sq_diff / range))

echo $normalized_variance
EOF
chmod +x calc_stats.sh

git add calc_stats.sh
git commit -m "Initial commit: Add calc_stats.sh"
git tag v1.0

# Add 5 dummy commits
for i in {1..5}; do
    echo "# comment $i" >> calc_stats.sh
    git commit -am "Dummy commit $i"
done

# Introduce the regression
cat << 'EOF' > calc_stats.sh
#!/bin/bash
# Calculate integer variance
input_file=$1
sum=0
count=0
while read -r num; do
    [ -z "$num" ] && continue
    sum=$((sum + num))
    count=$((count + 1))
done < "$input_file"

# BUG INTRODUCED HERE: mean=$((sum / (count + 1)))
mean=$((sum / (count + 1)))

sum_sq_diff=0
while read -r num; do
    [ -z "$num" ] && continue
    diff=$((num - mean))
    sq_diff=$((diff * diff))
    sum_sq_diff=$((sum_sq_diff + sq_diff))
done < "$input_file"

max=$(sort -n "$input_file" | tail -n1)
min=$(sort -n "$input_file" | head -n1)
range=$((max - min))
normalized_variance=$((sum_sq_diff / range))

echo $normalized_variance
EOF
git commit -am "Refactor mean calculation"
git tag bad-commit-tag

# Add 5 more dummy commits
for i in {6..10}; do
    echo "# comment $i" >> calc_stats.sh
    git commit -am "Dummy commit $i"
done

# Create aggregate_logs.sh and log chunks
mkdir -p chunks
true_sum=0
for i in {1..50}; do
    chunk_sum=0
    for j in {1..100}; do
        val=$RANDOM
        echo $val >> "chunks/chunk_$i.txt"
        true_sum=$((true_sum + val))
    done
done
echo "$true_sum" > /home/user/.secret_true_sum

cat << 'EOF' > aggregate_logs.sh
#!/bin/bash
echo 0 > global_sum.txt

for file in chunks/*.txt; do
    (
        local_sum=0
        while read -r num; do
            local_sum=$((local_sum + num))
        done < "$file"

        # RACE CONDITION HERE
        current_global=$(cat global_sum.txt)
        new_global=$((current_global + local_sum))
        echo $new_global > global_sum.txt
    ) &
done
wait
echo "Final sum: $(cat global_sum.txt)"
EOF
chmod +x aggregate_logs.sh
SETUP_EOF

bash /tmp/setup.sh

chown -R user:user /home/user/perf_math
chown -R user:user /home/user/
chmod -R 777 /home/user
