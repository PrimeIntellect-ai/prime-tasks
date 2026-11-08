#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Create the text file for the policy
    cat << 'EOF' > /app/waf_policy.txt
WAF POLICY ENFORCEMENT FLOW:
1. Reject if payload contains "DROP TABLE"
2. Reject if payload contains "<svg onload"
3. Remove all backtick characters (`)
4. Convert all space characters ( ) to underscores (_)
5. Output the final payload
EOF

    # Convert text to image
    convert -background white -fill black -font DejaVu-Sans -pointsize 18 text:/app/waf_policy.txt /app/waf_policy.png

    # Create the oracle
    cat << 'EOF' > /app/waf_oracle
#!/bin/bash
input="$1"
# Case insensitive rejection
shopt -s nocasematch
if [[ "$input" =~ "DROP TABLE" ]]; then
    echo "BLOCKED"
    exit 1
fi
if [[ "$input" =~ "<svg onload" ]]; then
    echo "BLOCKED"
    exit 1
fi
shopt -u nocasematch

# Transformations
# Remove backticks
output="${input//\`/}"
# Convert spaces to underscores
output="${output// /_}"

echo -n "$output"
exit 0
EOF
    chmod +x /app/waf_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
