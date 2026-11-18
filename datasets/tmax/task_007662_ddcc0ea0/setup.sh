#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/protein.fasta
>synthetic_protein_alpha_helix_test
MAAAKKKMMM
LQAERDAIIV
EOF

    cat << 'EOF' > /home/user/workflow.ipynb
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Run Pipeline\n",
    "This cell runs the spectral analysis on our target FASTA."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "#!/bin/bash\n",
    "/home/user/analyze_spectra.sh /home/user/protein.fasta > /home/user/spectral_output.txt\n"
   ]
  }
 ],
 "metadata": {
  "language_info": {
   "name": "bash"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 2
}
EOF

    chmod -R 777 /home/user
