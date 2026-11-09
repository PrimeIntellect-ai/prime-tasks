#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

# Add unpredictable artifacts so a hard-coded index cannot pass. These exercise the
# same traversal, extension, size, and first-32-byte requirements as the task.
python3 - <<'PY'
import os
import secrets

base = "/home/user/artifacts/safe_zone"
test_dir = os.path.join(base, ".verifier_" + secrets.token_hex(12))
os.makedirs(test_dir, exist_ok=False)

with open(os.path.join(test_dir, "generated_" + secrets.token_hex(8) + ".blob"), "wb") as f:
    f.write(os.urandom(32))
    f.write(os.urandom(100123 - 32))

with open(os.path.join(test_dir, "small_" + secrets.token_hex(8) + ".blob"), "wb") as f:
    f.write(os.urandom(99999))

with open(os.path.join(test_dir, "ignored_" + secrets.token_hex(8) + ".bin"), "wb") as f:
    f.write(os.urandom(100321))
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

SCRIPT_FILE = "/home/user/curate.py"
INDEX_FILE = "/home/user/curated_index.txt"
BASE_DIR = "/home/user/artifacts"

def get_expected_entries():
    """
    Derives the expected output by walking the directory tree,
    avoiding symlinks, and finding .blob files > 100,000 bytes.
    """
    entries = []
    for root, dirs, files in os.walk(BASE_DIR):
        for filename in files:
            if not filename.endswith(".blob"):
                continue

            filepath = os.path.join(root, filename)

            # Skip if it's a symlink
            if os.path.islink(filepath):
                continue

            try:
                size = os.path.getsize(filepath)
            except OSError:
                continue

            if size > 100000:
                with open(filepath, "rb") as f:
                    data = f.read(32)
                hex_str = data.hex()
                entries.append(f"{filepath}: {hex_str}")

    # Sort alphabetically by absolute file path
    entries.sort()
    return entries

def test_curate_script_exists():
    assert os.path.isfile(SCRIPT_FILE), f"Verification failed: {SCRIPT_FILE} not found."
    assert not os.path.islink(SCRIPT_FILE), f"Verification failed: {SCRIPT_FILE} must be a regular script."

def test_curated_index_exists():
    assert os.path.isfile(INDEX_FILE), f"Verification failed: {INDEX_FILE} not found."

def test_curated_index_contents():
    expected_lines = get_expected_entries()

    with open(INDEX_FILE, "r") as f:
        actual_content = f.read()

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
    expected_lines_stripped = [line.strip() for line in expected_lines]

    assert actual_lines == expected_lines_stripped, (
        f"Verification failed: The contents of {INDEX_FILE} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines_stripped)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )

def test_symlinks_untouched():
    link1 = os.path.join(BASE_DIR, "archive_A", "link_to_B")
    link2 = os.path.join(BASE_DIR, "archive_B", "nested", "link_to_A")

    assert os.path.islink(link1), f"Symlink was modified or removed: {link1}"
    assert os.path.islink(link2), f"Symlink was modified or removed: {link2}"

    assert os.readlink(link1) == os.path.join(BASE_DIR, "archive_B"), f"Symlink target was altered for {link1}"
    assert os.readlink(link2) == os.path.join(BASE_DIR, "archive_A"), f"Symlink target was altered for {link2}"
TEST_EOF

SCRIPT_FILE=/home/user/curate.py
INDEX_FILE=/home/user/curated_index.txt

# Remove any precomputed answer, then execute the submitted artifact under Python 3.
if [[ -f "$SCRIPT_FILE" && ! -L "$SCRIPT_FILE" ]] \
    && rm -f "$INDEX_FILE" \
    && timeout 10s runuser -u user -- bash -c 'cd /home/user && exec python3 /home/user/curate.py' \
    && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
