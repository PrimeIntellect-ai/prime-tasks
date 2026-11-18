#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest pandas numpy

    # Setup directories
    mkdir -p /app
    cd /app

    # Download and extract real third-party package using pip download
    pip3 download --no-binary :all: --no-deps fuzzywuzzy==0.18.0
    tar -xzf fuzzywuzzy-0.18.0.tar.gz
    mv fuzzywuzzy-0.18.0 fuzzywuzzy
    rm fuzzywuzzy-0.18.0.tar.gz

    # Inject deliberate perturbation: insert '    return 0' at the start of ratio function
    sed -i 's/def ratio(s1, s2):/def ratio(s1, s2):\n    return 0/g' /app/fuzzywuzzy/fuzzywuzzy/fuzz.py

    # Create user
    useradd -m -s /bin/bash user || true

    # Create datasets
    mkdir -p /home/user
    cat << 'EOF' > /home/user/data_A.csv
item_name
Apple iPhone 12
Samsung Galaxy S21
Sony PlayStation 5
Nintendo Switch OLED
Dell XPS 13
MacBook Air M1
Google Pixel 6
Amazon Echo Dot
Bose QuietComfort 35
Sony WH-1000XM4
EOF

    cat << 'EOF' > /home/user/data_B.csv
item_name
iPhone 12 Black
Samsung Galaxy S21 5G
PlayStation 5 Console
Nintendo Switch
Dell XPS 13 Laptop
Apple MacBook Air M1
Pixel 6 Pro
Echo Dot 4th Gen
Bose QC 35 II
Sony WH1000XM4
EOF

    cat << 'EOF' > /home/user/model_predictions.csv
item_A,item_B,predicted_match
Apple iPhone 12,iPhone 12 Black,1
Samsung Galaxy S21,Samsung Galaxy S21 5G,1
Sony PlayStation 5,PlayStation 5 Console,1
Nintendo Switch OLED,Nintendo Switch,1
Dell XPS 13,Dell XPS 13 Laptop,1
MacBook Air M1,Apple MacBook Air M1,1
Google Pixel 6,Pixel 6 Pro,1
Amazon Echo Dot,Echo Dot 4th Gen,1
Bose QuietComfort 35,Bose QC 35 II,1
Sony WH-1000XM4,Sony WH1000XM4,1
Apple iPhone 12,Nintendo Switch,0
Samsung Galaxy S21,Sony WH1000XM4,0
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
