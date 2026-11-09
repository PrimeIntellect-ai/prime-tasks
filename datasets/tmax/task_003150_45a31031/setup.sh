#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-setuptools
    pip3 install pytest

    python3 -c '
import os

os.makedirs("/app/unicodenorm-0.2.1/unicodenorm", exist_ok=True)

with open("/app/unicodenorm-0.2.1/setup.py", "w") as f:
    f.write("""from setuptools import setup, find_packages
setup(
    name="unicodenorm",
    version="0.2.1",
    packages=find_packages(),
    install_requires=["regex", "typing_extensions>=9999.0"]
)
""")

with open("/app/unicodenorm-0.2.1/unicodenorm/__init__.py", "w") as f:
    f.write("""import regex
def is_malicious(text: str) -> bool:
    # Detects directional formatting characters and unassigned/private use
    if regex.search(r"[\\u202A-\\u202E\\u2066-\\u2069]", text):
        return True
    return False
""")

os.makedirs("/var/opt/corpora/clean", exist_ok=True)
os.makedirs("/var/opt/corpora/evil", exist_ok=True)

with open("/var/opt/corpora/clean/valid.txt", "w", encoding="utf-8") as f:
    f.write("Hello world\nمرحبا بالعالم\n你好，世界\nThis is a normal sentence with some punctuation.\n")

with open("/var/opt/corpora/evil/malicious.txt", "w", encoding="utf-8") as f:
    f.write("Hello\u202Eworld\nabc!@#$%^&*()_+defg\nshort!@#$%\n")
'

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
