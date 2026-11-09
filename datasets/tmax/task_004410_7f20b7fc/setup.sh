#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_processor
    cd /home/user/data_processor
    git init
    git config user.email "eng@example.com"
    git config user.name "Engineer"

    # Commit 1 (Good)
    cat << 'EOF' > process_logs.sh
#!/bin/bash
sum=0
while read -r line; do
  sum=$((sum + line))
done < "$1"
echo "$sum"
EOF
    chmod +x process_logs.sh
    git add process_logs.sh
    git commit -m "Initial working script"
    GOOD_COMMIT=$(git rev-parse HEAD)

    # Commit 2
    echo "# This script calculates the sum of integers" >> process_logs.sh
    git commit -am "Add comment"

    # Commit 3 (Bad - introduces bug on input 1337)
    cat << 'EOF' > process_logs.sh
#!/bin/bash
# This script calculates the sum of integers
sum=0
while read -r line; do
  val=$line
  while [ "$val" -eq 1337 ]; do
    sleep 0.1
    # Bug: val is never updated, causing infinite loop
  done
  sum=$((sum + val))
done < "$1"
echo "$sum"
EOF
    git commit -am "Refactor to handle specific codes"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Commit 4
    echo "# End of script" >> process_logs.sh
    git commit -am "Add end comment"

    # Commit 5
    echo "# v1.1" >> process_logs.sh
    git commit -am "Version bump"

    # Save values for verification
    echo "1337" > /tmp/expected_hanging_input.txt
    echo "$BAD_COMMIT" > /tmp/expected_bad_commit.txt

    chmod -R 777 /home/user
