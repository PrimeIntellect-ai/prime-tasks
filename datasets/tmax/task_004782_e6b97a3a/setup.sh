#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core tesseract-ocr
    pip3 install pytest pytesseract

    mkdir -p /app

    # Create oracle script
    cat << 'EOF' > /app/oracle_fw_check
#!/usr/bin/env python3
import sys
import ipaddress

def main():
    if len(sys.argv) != 3:
        print("DROP")
        return

    source = sys.argv[1]
    dest_ip_str = sys.argv[2]

    rules = {
        "frontend": "172.16.10.0/24",
        "backend": "172.16.20.0/24",
        "database": "192.168.5.0/28"
    }

    if source not in rules:
        print("DROP")
        return

    try:
        dest_ip = ipaddress.IPv4Address(dest_ip_str)
        network = ipaddress.IPv4Network(rules[source])
        if dest_ip in network:
            print("ALLOW")
        else:
            print("DROP")
    except ValueError:
        print("DROP")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_fw_check

    # Fix ImageMagick policy to allow text to image
    sed -i 's/<policy domain="path" rights="none" pattern="@\*"/<!-- <policy domain="path" rights="none" pattern="@\*" -->/g' /etc/ImageMagick-6/policy.xml || true

    # Create the firewall rules image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 16 -fill black \
        -annotate +10+30 "Source Service | Allowed CIDR" \
        -annotate +10+60 "frontend       | 172.16.10.0/24" \
        -annotate +10+90 "backend        | 172.16.20.0/24" \
        -annotate +10+120 "database       | 192.168.5.0/28" \
        /app/firewall_rules.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
