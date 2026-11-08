#!/bin/bash
set -e
mkdir -p /logs/verifier

VALGRIND_PATH="$(command -v valgrind)"
REAL_VALGRIND="$(mktemp /tmp/real-valgrind.XXXXXX)"
VG_AUDIT_LOG="$(mktemp /tmp/valgrind-audit.XXXXXX)"
mv "$VALGRIND_PATH" "$REAL_VALGRIND"

cleanup() {
    rm -f "$VALGRIND_PATH" "$VG_AUDIT_LOG"
    if [ -e "$REAL_VALGRIND" ]; then
        mv "$REAL_VALGRIND" "$VALGRIND_PATH"
    fi
}
trap cleanup EXIT

cat > "$VALGRIND_PATH" << 'WRAPPER_EOF'
#!/bin/bash
input_copy="$(mktemp /tmp/valgrind-input.XXXXXX)"
cat > "$input_copy"
hash="$(sha256sum "$input_copy" | awk '{print $1}')"
printf '%s' "$hash" >> "$VG_AUDIT_LOG"
for arg in "$@"; do
    printf '\t%s' "$arg" >> "$VG_AUDIT_LOG"
done
printf '\n' >> "$VG_AUDIT_LOG"
"$REAL_VALGRIND" "$@" < "$input_copy"
status=$?
rm -f "$input_copy"
exit "$status"
WRAPPER_EOF
chmod 755 "$VALGRIND_PATH"
export REAL_VALGRIND VG_AUDIT_LOG

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import subprocess
import tempfile


def test_minimal_leak_file():
    path = "/home/user/minimal_leak.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip().split()

    assert content == ["837", "912"], f"Content of {path} is incorrect. Expected ['837', '912'], got {content}"


def test_test_leak_script_exists_and_executable():
    path = "/home/user/test_leak.sh"
    assert os.path.isfile(path), f"Missing script: {path}"
    assert os.access(path, os.X_OK), f"Script is not executable: {path}"


def test_test_leak_script_behavior():
    script_path = "/home/user/test_leak.sh"
    leak_file = "/home/user/minimal_leak.txt"

    # Test with the minimal leak file
    result_leak = subprocess.run([script_path, leak_file], capture_output=True)
    assert result_leak.returncode == 1, f"Expected {script_path} to exit with 1 on memory leak, but got {result_leak.returncode}"

    # Test with a clean file
    with tempfile.NamedTemporaryFile(mode='w', delete=False) as clean_file:
        clean_file.write("1\n2\n3\n")
        clean_path = clean_file.name

    try:
        result_clean = subprocess.run([script_path, clean_path], capture_output=True)
        assert result_clean.returncode == 0, f"Expected {script_path} to exit with 0 on no memory leak, but got {result_clean.returncode}"
    finally:
        os.remove(clean_path)


def trusted_leak_result(data):
    result = subprocess.run(
        [os.environ["REAL_VALGRIND"], "--leak-check=full", "--show-leak-kinds=definite", "/home/user/service"],
        input=data,
        capture_output=True,
        timeout=30,
    )
    output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    matches = re.findall(r"definitely lost:\s*([0-9,]+) bytes", output)
    assert matches, f"Trusted valgrind run did not produce a definitely-lost summary: {output}"
    return 1 if int(matches[-1].replace(",", "")) > 0 else 0


def assert_valgrind_received(data):
    expected_hash = hashlib.sha256(data).hexdigest()
    with open(os.environ["VG_AUDIT_LOG"], "r", errors="replace") as audit:
        records = [line.rstrip("\n").split("\t") for line in audit]
    assert any(
        record and record[0] == expected_hash and "/home/user/service" in record[1:]
        for record in records
    ), "test_leak.sh did not run /home/user/service under valgrind with the supplied input"


def test_script_uses_valgrind_and_handles_unseen_service_behavior():
    service_path = "/home/user/service"
    script_path = "/home/user/test_leak.sh"
    audit_path = os.environ["VG_AUDIT_LOG"]

    with open(service_path, "rb") as f:
        original_service = f.read()

    rng = random.SystemRandom()
    trigger_a = rng.randrange(100000, 900000)
    trigger_b = rng.randrange(100000, 900000)
    while trigger_b == trigger_a:
        trigger_b = rng.randrange(100000, 900000)
    filler = rng.randrange(100000, 900000)
    while filler in (trigger_a, trigger_b):
        filler = rng.randrange(100000, 900000)

    source = f'''#include <stdio.h>
#include <stdlib.h>
int main(void) {{
    int prev = 0, curr;
    while (scanf("%d", &curr) == 1) {{
        if (prev == {trigger_a} && curr == {trigger_b}) {{
            void *p = malloc(1024);
            __asm__ __volatile__("" : : "r"(p) : "memory");
        }}
        prev = curr;
    }}
    return 0;
}}
'''

    try:
        with tempfile.TemporaryDirectory() as td:
            source_path = os.path.join(td, "probe.c")
            binary_path = os.path.join(td, "probe")
            with open(source_path, "w") as f:
                f.write(source)
            subprocess.run(["gcc", "-g", "-O0", "-o", binary_path, source_path], check=True)
            with open(binary_path, "rb") as src, open(service_path, "wb") as dst:
                dst.write(src.read())
            os.chmod(service_path, 0o755)

        cases = [
            [trigger_a, trigger_b],
            [filler, trigger_a, trigger_b, filler + 1],
            [trigger_a, filler, trigger_b],
            [trigger_b, trigger_a, filler],
            [filler, filler + 1, filler + 2],
        ]

        for values in cases:
            data = ("".join(f"{value}\n" for value in values)).encode()
            expected = trusted_leak_result(data)
            with tempfile.NamedTemporaryFile(delete=False) as test_file:
                test_file.write(data)
                test_path = test_file.name
            try:
                open(audit_path, "w").close()
                result = subprocess.run([script_path, test_path], capture_output=True, timeout=30)
                assert result.returncode == expected, (
                    f"Expected exit {expected} for an unseen valgrind result, got {result.returncode}. "
                    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
                )
                assert_valgrind_received(data)
            finally:
                os.remove(test_path)
    finally:
        with open(service_path, "wb") as f:
            f.write(original_service)
        os.chmod(service_path, 0o755)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
