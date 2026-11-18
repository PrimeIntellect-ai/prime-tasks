#!/bin/bash
set -e
mkdir -p /logs/verifier

run_tests() {
    local original_so=/tmp/verifier-original-libstringops.so
    cp /home/user/libstringops.so "$original_so" || return 1
    trap 'cp /tmp/verifier-original-libstringops.so /home/user/libstringops.so 2>/dev/null || true' EXIT

    test -f /home/user/process.py || return 1

    # Recreate the specified input and generate both output.txt and valgrind.log
    # ourselves, so stale or fabricated artifacts cannot satisfy the checks.
    printf 'Hello\n' > /home/user/input.txt
    rm -f /home/user/output.txt /home/user/valgrind.log
    valgrind --leak-check=full --show-leak-kinds=all \
        --errors-for-leak-kinds=definite,indirect,possible --error-exitcode=97 \
        python3 /home/user/process.py /home/user/input.txt /home/user/output.txt \
        2> /home/user/valgrind.log || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re


def test_output_txt_content():
    path = "/home/user/output.txt"
    assert os.path.isfile(path), f"Output file {path} was not created."
    with open(path, "r") as f:
        content = f.read().strip()

    # "Hello" encoded as 16-bit LE hex:
    # H = 0x48 -> 4800
    # e = 0x65 -> 6500
    # l = 0x6c -> 6c00
    # l = 0x6c -> 6c00
    # o = 0x6f -> 6f00
    expected = "480065006c006c006f00"
    assert content.lower() == expected, f"Expected output '{expected}', but got '{content}'."


def test_valgrind_log_no_leaks():
    path = "/home/user/valgrind.log"
    assert os.path.isfile(path), f"Valgrind log file {path} was not created."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "definitely lost: 0 bytes in 0 blocks" in content, (
        "Valgrind log does not indicate that 0 bytes were definitely lost. "
        "Make sure memory is freed properly."
    )

    # Also require the other leak categories named by the task to be zero.
    for category in ("indirectly lost", "possibly lost"):
        assert re.search(rf"{category}:\s+0 bytes in 0 blocks", content), (
            f"Valgrind did not report zero bytes for {category}."
        )
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # Install a temporary ABI-compatible instrumented library. It returns a
    # run-specific 16-bit representation and records real encode/free calls.
    # A correct ctypes implementation remains generic and works unchanged.
    local mask
    mask=$(od -An -N1 -tu1 /dev/urandom | tr -d ' ')
    if [ "$mask" -eq 0 ]; then mask=173; fi

    cat > /tmp/verifier_stringops.c <<EOF
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint16_t *last_allocation = NULL;

static void mark(char value) {
    const char *path = getenv("STRINGOPS_TRACE");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (f) {
        fputc(value, f);
        fclose(f);
    }
}

uint16_t* encode_string(const char* input, int* out_len) {
    mark('E');
    if (!input) return NULL;
    size_t len = strlen(input);
    uint16_t *output = malloc((len + 1) * sizeof(uint16_t));
    if (!output) return NULL;
    for (size_t i = 0; i < len; ++i)
        output[i] = (uint16_t)((unsigned char)input[i]) | ((uint16_t)$mask << 8);
    output[len] = 0;
    if (out_len) *out_len = (int)len;
    last_allocation = output;
    return output;
}

void free_encoded(uint16_t* ptr) {
    if (ptr == last_allocation && ptr != NULL) {
        mark('F');
        last_allocation = NULL;
        free(ptr);
    } else {
        mark('X');
    }
}
EOF

    gcc -shared -fPIC -o /tmp/verifier-libstringops.so /tmp/verifier_stringops.c || return 1
    cp /tmp/verifier-libstringops.so /home/user/libstringops.so || return 1

    local dynamic_input=/tmp/verifier-input.txt
    local dynamic_output=/tmp/verifier-output.txt
    local dynamic_log=/tmp/verifier-valgrind.log
    local marker=/tmp/verifier-calls.log
    local text
    text="Probe$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')Z"
    printf '%s\n' "$text" > "$dynamic_input"
    rm -f "$dynamic_output" "$dynamic_log" "$marker"

    STRINGOPS_TRACE="$marker" valgrind --leak-check=full --show-leak-kinds=all \
        --errors-for-leak-kinds=definite,indirect,possible --error-exitcode=97 \
        python3 /home/user/process.py "$dynamic_input" "$dynamic_output" \
        2> "$dynamic_log" || return 1

    python3 - "$dynamic_input" "$dynamic_output" "$dynamic_log" "$marker" "$mask" <<'PY' || return 1
import re
import sys

input_path, output_path, log_path, marker_path, mask_text = sys.argv[1:]
mask = int(mask_text)
with open(input_path, "rb") as f:
    data = f.read().strip()
expected = b"".join(bytes((byte, mask)) for byte in data).hex()
with open(output_path, "r") as f:
    actual = f.read().strip().lower()
assert actual == expected, (expected, actual)

with open(marker_path, "r") as f:
    calls = f.read()
assert calls == "EF", f"Expected one encode_string call followed by its free_encoded call; got {calls!r}"

with open(log_path, "r") as f:
    log = f.read()
for category in ("definitely lost", "indirectly lost", "possibly lost"):
    assert re.search(rf"{category}:\s+0 bytes in 0 blocks", log), category
PY

    cp "$original_so" /home/user/libstringops.so || return 1
    trap - EXIT
    return 0
}

if run_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
