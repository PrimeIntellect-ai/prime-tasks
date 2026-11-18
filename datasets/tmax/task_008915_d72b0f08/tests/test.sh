#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_tracker.py
import os
import re
import resource
import shutil
import stat
import subprocess
import tempfile

HOME = "/home/user"
SOURCE = os.path.join(HOME, "tracker.c")
BINARY = os.path.join(HOME, "tracker")
CSV = os.path.join(HOME, "config_stream.csv")
REPORT = os.path.join(HOME, "report.html")


def expected_html(csv_path):
    state = {}
    output = []
    with open(csv_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) == 4:
                ts, srv, key, val = parts
                state_key = f"{srv}_{key}"
                if state.get(state_key) != val:
                    state[state_key] = val
                    output.append(
                        '<div class="change">\n'
                        f'  <span class="time">{ts}</span>\n'
                        f'  <span class="server">{srv}</span>\n'
                        f'  <span class="key">{key}</span>\n'
                        f'  <span class="value">{val}</span>\n'
                        '</div>\n'
                    )
    return ''.join(output)


def run_tracker(path, memory_mb=128, timeout=25):
    if os.path.exists(REPORT):
        os.remove(REPORT)

    def limits():
        limit = memory_mb * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_AS, (limit, limit))

    result = subprocess.run(
        [path], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout, preexec_fn=limits
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}.\n"
        f"stderr: {result.stderr.decode(errors='replace')[:2000]}"
    )
    assert os.path.exists(REPORT), f"{path} did not generate {REPORT}."


def check_report(expected):
    with open(REPORT, "r") as f:
        actual = f.read()
    assert actual == expected, (
        "The generated report.html does not match the expected deduplicated output.\n"
        "Ensure you are extracting state transitions correctly and matching the exact HTML format."
    )


def write_dynamic_case():
    token = os.urandom(8).hex()
    rows = [
        (f"9{token[:4]}", f"srv-{token[:3]}", "mode", "alpha"),
        (f"9{token[1:5]}", f"srv-{token[4:7]}", "limit", "17"),
        (f"9{token[2:6]}", f"srv-{token[:3]}", "mode", "alpha"),
        (f"9{token[3:7]}", f"srv-{token[:3]}", "mode", "beta"),
        (f"9{token[4:8]}", f"srv-{token[4:7]}", "limit", "17"),
        (f"9{token[5:9]}", f"srv-{token[4:7]}", "limit", "23"),
        (f"9{token[6:10]}", f"srv-{token[:3]}", "extra", token),
        (f"9{token[7:11]}", f"srv-{token[:3]}", "mode", "alpha"),
    ]
    with open(CSV, "w") as f:
        for row in rows:
            f.write(','.join(row) + "\n")


def stress_value(i):
    # A large comma-free value. Keeping all such raw values requires over 40 MiB,
    # while a hash-based tracker only retains one integer per key.
    unit = f"{i:08x}" + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123"
    return (unit * ((65536 // len(unit)) + 1))[:65536]


def write_stress_case(count=700):
    with open(CSV, "w") as f:
        for i in range(count):
            f.write(f"{2000000000+i},node-{i},setting,{stress_value(i)}\n")


def check_stress_report(count=700):
    with open(REPORT, "r") as f:
        for i in range(count):
            val = stress_value(i)
            expected = (
                '<div class="change">\n'
                f'  <span class="time">{2000000000+i}</span>\n'
                f'  <span class="server">node-{i}</span>\n'
                '  <span class="key">setting</span>\n'
                f'  <span class="value">{val}</span>\n'
                '</div>\n'
            )
            actual = f.read(len(expected))
            assert actual == expected, f"Incorrect stress-test output at record {i}."
        assert f.read(1) == "", "The stress-test report contains extra output."


def main():
    # Preserve the original existence and fixed-input report assertions.
    assert os.path.exists(SOURCE), "The source file /home/user/tracker.c does not exist."
    assert os.path.exists(CSV), f"Input file {CSV} is missing."
    assert os.path.exists(REPORT), f"Output file {REPORT} was not generated."
    check_report(expected_html(CSV))

    assert os.path.isfile(BINARY), "The compiled program /home/user/tracker does not exist."
    assert os.access(BINARY, os.X_OK), "/home/user/tracker is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/tracker is not a compiled ELF executable."

    with open(SOURCE, "r", errors="replace") as f:
        source_text = f.read()
    lower = source_text.lower()
    assert "hash" in lower, "tracker.c does not contain a hash-based state implementation."
    assert re.search(r"\b(uint32_t|uint64_t|uint_fast32_t|uint_fast64_t|size_t|unsigned\s+int|unsigned\s+long(?:\s+long)?)\b", source_text), (
        "tracker.c does not show a 32-bit or 64-bit integer representation for hashed state."
    )

    compiled = "/tmp/tracker_from_source"
    build = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", compiled],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, (
        "tracker.c could not be compiled with gcc.\n" +
        build.stderr.decode(errors="replace")[:3000]
    )

    csv_backup = open(CSV, "rb").read()
    report_backup = open(REPORT, "rb").read()
    try:
        # Exercise both the submitted executable and a fresh build of its source
        # on an unpredictable input, preventing a fixed hardcoded report.
        write_dynamic_case()
        dynamic_expected = expected_html(CSV)
        for executable in (BINARY, compiled):
            run_tracker(executable)
            check_report(dynamic_expected)

        # Under this limit, retaining every 64 KiB ConfigValue cannot succeed;
        # retaining only integer hashes and streaming each line can.
        write_stress_case()
        for executable in (BINARY, compiled):
            run_tracker(executable, memory_mb=32, timeout=45)
            check_stress_report()
    finally:
        with open(CSV, "wb") as f:
            f.write(csv_backup)
        with open(REPORT, "wb") as f:
            f.write(report_backup)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_tracker.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
