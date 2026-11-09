#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar gawk

    # Install pytest and papermill dependencies
    pip3 install pytest setuptools wheel
    pip3 install papermill==2.3.4
    # Uninstall papermill so the user has to install the vendored version, but keep dependencies
    pip3 uninstall -y papermill

    # Download and vendor papermill 2.3.4
    mkdir -p /app/vendored
    cd /app/vendored
    wget https://files.pythonhosted.org/packages/source/p/papermill/papermill-2.3.4.tar.gz
    tar -xzf papermill-2.3.4.tar.gz
    rm papermill-2.3.4.tar.gz

    # Introduce deliberate typo in cli.py
    sed -i 's/import click/import clik/g' /app/vendored/papermill-2.3.4/papermill/cli.py

    # Create corpora directories and files
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Clean files
    for i in $(seq 1 10); do
        cat <<EOF > /app/corpora/clean/clean_${i}.csv
1.0, 0.5
2.0, 0.8
3.0, 1.2
4.0, 1.5
EOF
    done

    # Evil files (unordered and NaN/Inf)
    for i in $(seq 1 5); do
        cat <<EOF > /app/corpora/evil/evil_unordered_${i}.csv
1.0, 0.5
3.0, 1.2
2.0, 0.8
4.0, 1.5
EOF
        cat <<EOF > /app/corpora/evil/evil_nan_${i}.csv
1.0, 0.5
2.0, NaN
3.0, 1.2
4.0, Inf
EOF
    done

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create stub notebook
    cat << 'EOF' > /home/user/fit_model.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {
    "tags": ["parameters"]
   },
   "outputs": [],
   "source": [
    "input_file = \"\""
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "print(\"Processing\", input_file)"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
