#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr g++ fonts-liberation
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate etl_rules.png
    convert -size 600x200 xc:white -fill black -pointsize 18 -draw "text 10,30 'SECURITY AND BUSINESS RULES:' text 10,60 '1. Amount must be a positive number (>= 0).' text 10,90 '2. Department must be exactly one of: SALES, IT, HR.' text 10,120 '3. CustomerName must NOT contain the characters \"<\" or \">\" to prevent injection.'" /app/etl_rules.png

    # Generate clean CSVs
    cat << 'EOF' > /app/corpus/clean/clean_1.csv
TransactionID,CustomerName,Department,Amount
101,John Doe,SALES,150.50
102,Jane Smith,IT,200.00
101,John Doe,SALES,150.50
EOF

    cat << 'EOF' > /app/corpus/clean/clean_2.csv
TransactionID,CustomerName,Department,Amount
201,Alice,HR,0.00
202,Bob,SALES,10.00
EOF

    # Generate evil CSVs
    cat << 'EOF' > /app/corpus/evil/evil_1.csv
TransactionID,CustomerName,Department,Amount
301,Bad Guy,IT,-50.00
EOF

    cat << 'EOF' > /app/corpus/evil/evil_2.csv
TransactionID,CustomerName,Department,Amount
302,Wrong Dept,MARKETING,100.00
EOF

    cat << 'EOF' > /app/corpus/evil/evil_3.csv
TransactionID,CustomerName,Department,Amount
303,<script>alert(1)</script>,HR,50.00
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
