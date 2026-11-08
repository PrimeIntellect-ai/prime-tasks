#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu john gawk sed coreutils
pip3 install pytest

mkdir -p /app
# Generate intercepted_hash.png
convert -size 400x100 xc:black -font DejaVu-Sans-Mono -pointsize 16 -fill green -draw "text 10,50 'admin:\$1\$salt\$wA0Hq9I8e20O.L8G.mE9o0'" /app/intercepted_hash.png

# Create oracle script /app/oracle_csp.sh
cat << 'EOF' > /app/oracle_csp.sh
#!/bin/bash
webroot=$1
header=$2
pin="8492"

csp="Content-Security-Policy: default-src 'self';"
for dir in "$webroot"/*/; do
    [ -d "$dir" ] || continue
    dirname=$(basename "$dir")
    perms=$(stat -c "%A" "$dir")

    if [[ $perms == *w* ]]; then
        if [ "$(stat -c "%a" "$dir" | cut -c 3)" -ge 2 ]; then
            # World writable logic
            if [[ $perms =~ .w. ]]; then
                 csp="$csp script-src-elem 'none' /$dirname;"
            fi
        fi
    fi
    # Quick fix for exact matching
    if [[ $(find "$dir" -maxdepth 0 -perm -0002) ]]; then
        csp="$csp script-src-elem 'none' /$dirname;"
    fi
    if [[ $(find "$dir" -maxdepth 0 -perm -1000) ]]; then
        csp="$csp object-src 'none';"
    fi
done

awk -v csp="$csp" -v pin="$pin" '
BEGIN { RS="\r?\n"; ORS="\r\n" }
/^$/ {
    if (!done) {
        print csp
        print "X-Admin-Pin: " pin
        done=1
    }
}
{ print $0 }
' "$header"
EOF
chmod +x /app/oracle_csp.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
