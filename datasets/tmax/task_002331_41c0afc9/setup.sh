#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib

    # Create directories
    mkdir -p /app/fast_svd_custom-0.1.0/fast_svd_custom
    mkdir -p /app/fast_svd_custom-0.1.0/tests
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate files using python
    python3 -c '
import os
import numpy as np

# Setup package
pkg_dir = "/app/fast_svd_custom-0.1.0"

with open(f"{pkg_dir}/README.md", "w", encoding="utf-8") as f:
    f.write("Fast SVD Custom 🚀\n")

with open(f"{pkg_dir}/setup.py", "w", encoding="utf-8") as f:
    f.write("""from setuptools import setup, find_packages

with open("README.md") as f:
    long_description = f.read()

setup(
    name="fast_svd_custom",
    version="0.1.0",
    packages=find_packages(),
    install_requires=["numpy", "scipy"],
    long_description=long_description,
    long_description_content_type="text/markdown",
)
""")

with open(f"{pkg_dir}/fast_svd_custom/__init__.py", "w", encoding="utf-8") as f:
    f.write("""import numpy as np
from scipy import linalg

def get_svd(matrix):
    return linalg.svd(matrix)
""")

with open(f"{pkg_dir}/tests/test_svd.py", "w", encoding="utf-8") as f:
    f.write("""import numpy as np
from fast_svd_custom import get_svd

def test_svd():
    a = np.eye(2)
    u, s, vh = get_svd(a)
    assert np.allclose(s, [1, 1])
""")

# Setup corpus
clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

np.random.seed(42)
for i in range(5):
    # clean: symmetric positive definite
    A = np.random.rand(5, 5)
    clean_mat = np.dot(A, A.T) + np.eye(5) * 0.1
    np.save(f"{clean_dir}/clean_{i}.npy", clean_mat)

    # evil: asymmetric or negative eigenvalues
    if i % 2 == 0:
        # asymmetric
        evil_mat = np.random.rand(5, 5)
        np.save(f"{evil_dir}/evil_{i}.npy", evil_mat)
    else:
        # symmetric but not PD
        A = np.random.rand(5, 5)
        evil_mat = np.dot(A, A.T)
        evil_mat[0, 0] = -10.0
        np.save(f"{evil_dir}/evil_{i}.npy", evil_mat)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
