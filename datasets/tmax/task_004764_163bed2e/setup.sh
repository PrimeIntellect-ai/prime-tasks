#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate rules.png
    # Allow imagemagick to read/write text/fonts
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/g' /etc/ImageMagick-6/policy.xml || true
    convert -background white -fill black -font Liberation-Sans -pointsize 24 label:"SECURITY MEMO\n\nRESTRICTED TABLES:\nsys_config\nuser_passwords\n\nFORBIDDEN FUNCTIONS:\npg_sleep\ndbms_lock.sleep" /app/rules.png

    # Generate clean CSVs
    for i in {1..5}; do
        cat <<EOF > /app/corpora/clean/clean_$i.csv
query_id,query_text
1,SELECT * FROM public_users;
2,SELECT id FROM orders;
3,SELECT name FROM products WHERE price > 10;
EOF
    done

    # Generate evil CSVs
    cat <<EOF > /app/corpora/evil/evil_1.csv
query_id,query_text
1,SELECT * FROM public_users;
2,SELECT * FROM UsEr_PaSsWoRdS;
EOF

    cat <<EOF > /app/corpora/evil/evil_2.csv
query_id,query_text
1,SELECT pg_sleep(10);
EOF

    cat <<EOF > /app/corpora/evil/evil_3.csv
query_id,query_text
1,SELECT * FROM orders JOIN sys_config ON 1=1;
EOF

    cat <<EOF > /app/corpora/evil/evil_4.csv
query_id,query_text
1,SELECT DBMS_LOCK.SLEEP(10);
EOF

    cat <<EOF > /app/corpora/evil/evil_5.csv
query_id,query_text
1,SELECT * FROM public_users;
2,SELECT * FROM SyS_CoNfIg;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
