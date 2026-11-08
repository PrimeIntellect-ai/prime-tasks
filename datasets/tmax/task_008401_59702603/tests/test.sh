#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_restored_docs_content():
    output_path = "/home/user/restored_docs.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. The script must create this file."

    with open(output_path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_content = "System Architecture Overview\nAPI Integration Guidelines"

    assert content.strip() == expected_content, (
        f"The content of {output_path} does not match the expected decompressed text.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{content}"
    )

def test_go_script_exists():
    script_path = "/home/user/restore.go"
    assert os.path.isfile(script_path), f"The Go script at {script_path} is missing."
TEST_EOF

success=1
if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    success=0
fi

if [ "$success" -eq 1 ]; then
    if ! python3 << 'PY_EOF'
import base64
import os
import secrets

case_root = "/home/user/.verifier_case_" + secrets.token_hex(8)
v1 = os.path.join(case_root, "real", "v1")
v2 = os.path.join(case_root, "real", "v2")
os.makedirs(v1)
os.makedirs(v2)

os.symlink(v2, os.path.join(case_root, "latest"))
os.symlink("../v1", os.path.join(v2, "prev"))
os.symlink("../v2", os.path.join(v1, "next"))

texts = [
    "Architecture-" + secrets.token_hex(18),
    "Integration-" + secrets.token_hex(21),
    "Operations-" + secrets.token_hex(16),
]
ignored = "Ignored-" + secrets.token_hex(20)

def encode_tdz(text):
    transformed = bytes((value + 1) % 256 for value in text.encode("utf-8"))
    return base64.b64encode(transformed).decode("ascii")

files = [
    (os.path.join(v1, "dynamic_a.tdz"), texts[0]),
    (os.path.join(v2, "dynamic_b.tdz"), texts[1]),
    (os.path.join(v1, "dynamic_c.tdz"), texts[2]),
    (os.path.join(v1, "ignored.tdz"), ignored),
]
for path, text in files:
    with open(path, "w", encoding="ascii") as f:
        f.write(encode_tdz(text))

targets = [
    os.path.join(case_root, "latest", "prev", "next", "prev", "dynamic_a.tdz"),
    os.path.join(case_root, "real", "v1", "next", "prev", "ignored.tdz"),
    os.path.join(case_root, "real", "v1", "next", "prev", "next", "dynamic_b.tdz"),
    os.path.join(case_root, "latest", "prev", "dynamic_c.tdz"),
]
statuses = ["DECOMPRESS", "IGNORE", "DECOMPRESS", "DECOMPRESS"]
authors = ["Verifier Alice", "Verifier Bob", "Verifier Charlie", "Verifier Dana"]

with open("/home/user/backup.log", "w", encoding="utf-8") as f:
    for target, status, author in zip(targets, statuses, authors):
        f.write("===RECORD START===\n")
        f.write(f"Target: {target}\n")
        f.write(f"Status: {status}\n")
        f.write(f"Author: {author}\n")
        f.write("===RECORD END===\n")

with open("/tmp/verifier_expected.txt", "w", encoding="utf-8") as f:
    f.write("\n".join(texts))

try:
    os.remove("/home/user/restored_docs.txt")
except FileNotFoundError:
    pass
PY_EOF
    then
        success=0
    fi
fi

if [ "$success" -eq 1 ]; then
    if ! (cd /home/user && timeout 30s go run /home/user/restore.go); then
        success=0
    fi
fi

if [ "$success" -eq 1 ]; then
    if ! python3 << 'PY_EOF'
import os

output_path = "/home/user/restored_docs.txt"
assert os.path.isfile(output_path), "Executing restore.go did not create restored_docs.txt"
with open(output_path, "r", encoding="utf-8") as f:
    actual = f.read()
with open("/tmp/verifier_expected.txt", "r", encoding="utf-8") as f:
    expected = f.read()
assert actual.strip() == expected, (
    "restore.go did not parse and decompress the randomized log targets correctly.\n"
    f"Expected:\n{expected}\nGot:\n{actual}"
)
PY_EOF
    then
        success=0
    fi
fi

if [ "$success" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
