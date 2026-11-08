#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the malicious zip file
    python3 -c "
import zipfile
import os

zip_path = '/home/user/incoming.zip'
with zipfile.ZipFile(zip_path, 'w') as zf:
    zf.writestr('valid_file.txt', 'This is a valid file.')
    zf.writestr('nested/deep_file.txt', 'This is a deep file.')
    zf.writestr('../escaped_file.txt', 'This file should not be extracted.')
    zf.writestr('nested/../../../sneaky.txt', 'This is also outside.')
"

    chmod -R 777 /home/user
