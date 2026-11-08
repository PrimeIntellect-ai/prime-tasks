#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project
    cd /home/user/project

    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Commit 1: Initial setup with hardcoded token and correct dir
    mkdir -p tests
    touch tests/test_main.py
    cat << 'EOF' > build.py
import os

CI_TOKEN = "ci-token-9988776655"
TEST_DIR = "tests/"

def run_build():
    if CI_TOKEN != "ci-token-9988776655":
        print("Build failed: Invalid token")
        exit(1)
    if not os.path.isdir(TEST_DIR):
        print(f"Build failed: Test directory {TEST_DIR} not found")
        exit(1)

    with open("/home/user/success.txt", "w") as f:
        f.write("BUILD_PASS_774\n")
    print("Build succeeded!")

if __name__ == "__main__":
    run_build()
EOF
    git add .
    git commit -m "Initial commit"

    # Commit 2: Restructure tests
    mv tests test
    git add .
    git commit -m "Rename tests directory to test"

    # Commit 3: Remove token and introduce path bug
    cat << 'EOF' > build.py
import os

CI_TOKEN = os.environ.get("CI_TOKEN", "")
TEST_DIR = "tests/" # BUG: Should be "test/"

def run_build():
    if CI_TOKEN != "ci-token-9988776655":
        print("Build failed: Invalid token")
        exit(1)
    if not os.path.isdir(TEST_DIR):
        print(f"Build failed: Test directory {TEST_DIR} not found")
        exit(1)

    with open("/home/user/success.txt", "w") as f:
        f.write("BUILD_PASS_774\n")
    print("Build succeeded!")

if __name__ == "__main__":
    run_build()
EOF
    git add build.py
    git commit -m "Secure CI token and update build script"

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
