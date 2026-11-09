#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-liberation tesseract-ocr socat netcat-openbsd curl jq
    pip3 install pytest jupyter nbconvert

    mkdir -p /app

    # Generate the reference gel image
    convert -size 400x100 xc:white -fill black -pointsize 24 -annotate +20+50 "TARGET_SEQ: ACTGGCCTTAACGGAT" /app/reference_gel.png

    # Create candidates.csv
    cat << 'EOF' > /app/candidates.csv
ID_001,ACTGGCCTTAACGGAT
ID_002,ACTGGCCTTAACGGA
ID_003,ACTGGCCTTAACGG
ID_004,ACTGGCCTTAACG
ID_005,ACTGGCCTTAACGGATGC
ID_006,ACTGGCCTTAACGGATGCG
ID_007,CCTGGCCTTAACGGAT
EOF

    # Create regression.ipynb
    cat << 'EOF' > /app/regression.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import os\n",
    "assert os.path.exists('/app/target_sequence.txt'), 'Target sequence file not found'\n",
    "with open('/app/target_sequence.txt', 'r') as f:\n",
    "    seq = f.read().strip()\n",
    "assert seq == 'ACTGGCCTTAACGGAT', f'Incorrect sequence extracted: {seq}'\n",
    "print('Regression test passed.')"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.10.6"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
