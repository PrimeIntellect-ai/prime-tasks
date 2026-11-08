#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

ORIGINAL_SOURCE = b'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_file(const char *filename, const char *out_filename) {
    FILE *f = fopen(filename, "rb");
    FILE *out = fopen(out_filename, "wb");
    if(!f || !out) return;

    unsigned char magic[2];
    while (fread(magic, 1, 2, f) == 2) {
        if (magic[0] != 'L' || magic[1] != 'G') break;
        unsigned char type;
        if (fread(&type, 1, 1, f) != 1) break;
        unsigned char len;
        if (fread(&len, 1, 1, f) != 1) break;

        unsigned char payload[256];
        if (fread(payload, 1, len, f) != len) break;

        if (type == 1) {
            for (int i = 0; i < len / 2; i++) {
                unsigned char tmp = payload[i];
                payload[i] = payload[len - 1 - i];
                payload[len - 1 - i] = tmp;
            }
        } else if (type == 3) {
            int out_len = 0;
            unsigned char decoded[1024];
            for(int i=0; i<len; i+=2) {
                unsigned char count = payload[i];
                unsigned char val = payload[i+1];
                for(int j=0; j<count; j++) {
                    decoded[out_len++] = val; 
                }
            }
            fwrite(decoded, 1, out_len, out);
            continue;
        }

        fwrite(&type, 1, 1, out);
        fwrite(&len, 1, 1, out);
        fwrite(payload, 1, len, out);
    }
    fclose(f);
    fclose(out);
}

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    process_file(argv[1], argv[2]);
    return 0;
}
'''

EXPECTED_CRASH = b"LG\x03\x0a" + b"\xff\xaa" * 5
EXPECTED_DATA = b"LG\x01\x04\x01\x02\x03\x04"
EXPECTED_DATA_OUTPUT = b"\x01\x04\x04\x03\x02\x01"


def run_program(executable, input_bytes):
    with tempfile.TemporaryDirectory() as td:
        inp = os.path.join(td, "input.bin")
        out = os.path.join(td, "output.bin")
        with open(inp, "wb") as f:
            f.write(input_bytes)
        result = subprocess.run(
            [executable, inp, out], capture_output=True, timeout=5
        )
        content = None
        if os.path.isfile(out):
            with open(out, "rb") as f:
                content = f.read()
        return result, content


def record(record_type, payload):
    assert len(payload) <= 255
    return b"LG" + bytes([record_type, len(payload)]) + payload


def expected_transform(records):
    output = bytearray()
    for record_type, payload in records:
        if record_type == 1:
            transformed = payload[::-1]
            output.extend(bytes([record_type, len(payload)]))
            output.extend(transformed)
        elif record_type == 3:
            decoded = bytearray()
            for i in range(0, len(payload), 2):
                count = payload[i]
                value = payload[i + 1]
                available = 1024 - len(decoded)
                if available <= 0:
                    break
                decoded.extend(bytes([value]) * min(count, available))
            output.extend(decoded)
        else:
            output.extend(bytes([record_type, len(payload)]))
            output.extend(payload)
    return bytes(output)


def encode_records(records):
    return b"".join(record(t, p) for t, p in records)


def compile_fixed_source(output_path):
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/log_ingestor_fixed.c", "-o", output_path],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, "Failed to compile log_ingestor_fixed.c:\n" + result.stderr


def test_minimized_bin_crashes_original():
    min_bin = "/home/user/minimized.bin"
    assert os.path.isfile(min_bin), "minimized.bin not found at /home/user/minimized.bin"

    size = os.path.getsize(min_bin)
    assert size <= 50, f"minimized.bin is too large ({size} bytes) to be minimal."

    with open(min_bin, "rb") as f:
        minimized = f.read()
    assert minimized == EXPECTED_CRASH, (
        "minimized.bin is not the exact minimal valid crashing record from crash.bin"
    )
    assert minimized[:2] == b"LG" and minimized[2] == 3
    assert minimized[3] == len(minimized) - 4
    assert minimized[3] % 2 == 0

    with open("/home/user/crash.bin", "rb") as f:
        assert f.read() == EXPECTED_CRASH, "crash.bin was modified"
    with open("/home/user/data.bin", "rb") as f:
        assert f.read() == EXPECTED_DATA, "data.bin was modified"

    orig_c = "/home/user/log_ingestor.c"
    with open(orig_c, "rb") as f:
        assert f.read() == ORIGINAL_SOURCE, "The original log_ingestor.c was modified"

    orig_bin = "/tmp/log_ingestor_orig"
    compile_res = subprocess.run(["gcc", orig_c, "-o", orig_bin], capture_output=True)
    assert compile_res.returncode == 0, "Failed to compile the original log_ingestor.c"

    result, _ = run_program(orig_bin, minimized)
    assert result.returncode != 0, "minimized.bin did not cause the original binary to crash."
    assert result.returncode < 0, "Original binary failed without being terminated by a crash signal"

    # Four complete 255-byte runs total only 1020 decoded bytes and are the
    # largest valid record obtainable before the fifth run is required.
    smaller = record(3, b"\xff\xaa" * 4)
    smaller_result, smaller_output = run_program(orig_bin, smaller)
    assert smaller_result.returncode == 0, "A smaller non-overflowing record unexpectedly crashed"
    assert smaller_output == b"\xaa" * 1020


def test_fixed_binary_handles_crash_bin():
    fixed_bin = "/home/user/log_ingestor_fixed"
    assert os.path.isfile(fixed_bin), "Fixed binary not found at /home/user/log_ingestor_fixed"
    assert os.access(fixed_bin, os.X_OK), "Fixed binary is not executable"
    with open(fixed_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_ingestor_fixed is not a compiled ELF executable"

    out_file = "/tmp/out_fixed.bin"
    if os.path.exists(out_file):
        os.remove(out_file)
    result = subprocess.run(
        [fixed_bin, "/home/user/crash.bin", out_file], capture_output=True, timeout=5
    )
    assert result.returncode == 0, "Fixed binary crashed or failed when processing crash.bin"
    assert os.path.isfile(out_file), "Fixed binary did not produce output for crash.bin"
    with open(out_file, "rb") as f:
        content = f.read()
    assert len(content) == 1024, (
        f"Expected output length to be capped at exactly 1024 bytes, got {len(content)} bytes."
    )
    assert all(b == 0xaa for b in content), "Decoded output content does not match the expected payload."


def test_data_fixed_bin_content():
    data_fixed = "/home/user/data_fixed.bin"
    assert os.path.isfile(data_fixed), "data_fixed.bin not found at /home/user/data_fixed.bin"
    with open(data_fixed, "rb") as f:
        content = f.read()
    assert content == EXPECTED_DATA_OUTPUT, (
        f"data_fixed.bin content mismatch. Expected {EXPECTED_DATA_OUTPUT}, got {content}"
    )

    result, generated = run_program("/home/user/log_ingestor_fixed", EXPECTED_DATA)
    assert result.returncode == 0
    assert generated == content, "data_fixed.bin was not produced by the submitted fixed behavior"


def test_fixed_code_exists():
    fixed_c = "/home/user/log_ingestor_fixed.c"
    assert os.path.isfile(fixed_c), f"Fixed source code not found at {fixed_c}"
    assert os.path.getsize(fixed_c) > 0, "Fixed source code is empty"


def test_compiled_source_and_installed_binary_handle_general_inputs():
    compiled = "/tmp/log_ingestor_fixed_from_source"
    compile_fixed_source(compiled)

    cases = []
    cases.append([(1, b"abcdef"), (2, b"unchanged"), (3, bytes([3, 0x41, 2, 0x42]))])
    cases.append([(3, bytes([255, 1]) * 4 + bytes([4, 2]))])
    cases.append([(3, bytes([250, 0x31]) * 4 + bytes([50, 0x32, 200, 0x33]))])
    cases.append([
        (3, bytes([255, 0x55]) * 5),
        (1, bytes(range(32))),
        (3, bytes([1, 0x99, 0, 0x22, 2, 0x77])),
    ])
    cases.append([(3, b""), (2, b""), (1, b"")])

    rng = random.Random(0xC0FFEE)
    for _ in range(30):
        records = []
        for _ in range(rng.randint(1, 5)):
            record_type = rng.choice([1, 2, 3, 3, 3, 7])
            if record_type == 3:
                pairs = rng.randint(0, 60)
                payload = bytearray()
                for _ in range(pairs):
                    payload.extend((rng.randint(0, 255), rng.randint(0, 255)))
                payload = bytes(payload)
            else:
                payload = bytes(rng.randrange(256) for _ in range(rng.randint(0, 100)))
            records.append((record_type, payload))
        cases.append(records)

    for executable in (compiled, "/home/user/log_ingestor_fixed"):
        for index, records in enumerate(cases):
            input_bytes = encode_records(records)
            expected = expected_transform(records)
            result, actual = run_program(executable, input_bytes)
            assert result.returncode == 0, (
                f"{executable} failed general case {index}: {result.stderr!r}"
            )
            assert actual == expected, (
                f"{executable} produced incorrect output for general case {index}: "
                f"expected {expected!r}, got {actual!r}"
            )


if __name__ == "__main__":
    raise SystemExit(1)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
