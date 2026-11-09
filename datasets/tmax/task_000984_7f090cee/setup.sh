#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uptime-monitor
    cd /home/user/uptime-monitor
    git init
    git config user.name "SRE Team"
    git config user.email "sre@example.com"

    # Commit 1: Initial working version
    cat << 'EOF' > uptime_calc.sh
#!/bin/bash
if [ "$2" -eq 0 ]; then echo "0.00"; exit 0; fi
awk -v succ="$1" -v tot="$2" 'BEGIN { printf "%.2f\n", (succ/tot)*100 }'
EOF
    chmod +x uptime_calc.sh
    git add uptime_calc.sh
    git commit -m "Initial uptime calculation script"

    # Commit 2: Add usage instructions
    cat << 'EOF' > uptime_calc.sh
#!/bin/bash
# Usage: ./uptime_calc.sh <success> <total>
if [ "$2" -eq 0 ]; then echo "0.00"; exit 0; fi
awk -v succ="$1" -v tot="$2" 'BEGIN { printf "%.2f\n", (succ/tot)*100 }'
EOF
    git add uptime_calc.sh
    git commit -m "Add usage instructions"

    # Commit 3: The BAD commit (introduces precision loss bug)
    cat << 'EOF' > uptime_calc.sh
#!/bin/bash
# Usage: ./uptime_calc.sh <success> <total>
if [ "$2" -eq 0 ]; then echo "0.00"; exit 0; fi
# Optimized to use native bash math
echo $(( ($1 / $2) * 100 )).00
EOF
    git add uptime_calc.sh
    git commit -m "Refactor calculation to avoid external dependencies"

    # Commit 4: Unrelated formatting change
    cat << 'EOF' > uptime_calc.sh
#!/bin/bash
# Usage: ./uptime_calc.sh <success> <total>
# Calculates uptime percentage
if [ "$2" -eq 0 ]; then echo "0.00"; exit 0; fi
# Optimized to use native bash math
echo $(( ($1 / $2) * 100 )).00
EOF
    git add uptime_calc.sh
    git commit -m "Add descriptive comments"

    # Commit 5: Unrelated typo fix
    cat << 'EOF' > uptime_calc.sh
#!/bin/bash
# Usage: ./uptime_calc.sh <success_count> <total_count>
# Calculates uptime percentage
if [ "$2" -eq 0 ]; then echo "0.00"; exit 0; fi
# Optimized to use native bash math
echo $(( ($1 / $2) * 100 )).00
EOF
    git add uptime_calc.sh
    git commit -m "Fix variable naming in comments"

    chown -R user:user /home/user/uptime-monitor
    chmod -R 777 /home/user
