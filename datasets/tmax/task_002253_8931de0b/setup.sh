#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_locales.txt
  MAIN_MENU_PLAY :   Play Game  
invalid-key : This should be dropped
MAIN_MENU_OPTIONS: Options
ERR_FILE_MISSING   :   Error: File not found
  MAIN_MENU_PLAY :   Start Game
lower_case_key : drop this too
VALID_EMPTY : 
TRICKY_VAL : This value has : a colon
ONLY_KEY_NO_COLON
EOF

    chmod -R 777 /home/user
