#!/bin/bash
mkdir -p /logs/verifier

verify() {
  cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_cpp_source_exists():
    """Verify that the C++ source file exists."""
    source_path = "/home/user/vuln_scanner.cpp"
    assert os.path.isfile(source_path), f"C++ source file {source_path} does not exist."

def test_compiled_binary_exists():
    """Verify that the compiled binary exists and is executable."""
    binary_path = "/home/user/vuln_scanner"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"Compiled binary {binary_path} is not executable."

def test_scan_results_file_exists():
    """Verify that the scan results file exists."""
    results_path = "/home/user/scan_results.txt"
    assert os.path.isfile(results_path), f"Scan results file {results_path} does not exist."

def test_scan_results_content():
    """Verify the content of the scan results file matches the expected output."""
    results_path = "/home/user/scan_results.txt"
    assert os.path.isfile(results_path), f"Scan results file {results_path} does not exist."

    expected_content = [
        "fake_bin: SUID=Yes, SHADOW_IN_RODATA=No",
        "safe_bin: SUID=No, SHADOW_IN_RODATA=No",
        "suid_bin: SUID=Yes, SHADOW_IN_RODATA=Yes"
    ]

    with open(results_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_content, f"Content of {results_path} does not match the expected output. Got: {lines}"
TEST_EOF

  python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

  # Build the submitted source using the exact command required by the task.
  g++ -std=c++17 /home/user/vuln_scanner.cpp -o /home/user/vuln_scanner || return 1

  python3 << 'PY_EOF'
import os
import secrets
import shutil
import stat
import struct
import subprocess
import tempfile

scanner = "/home/user/vuln_scanner"
targets = "/home/user/targets"
results = "/home/user/scan_results.txt"

with open(scanner, "rb") as f:
    ident = f.read(5)
assert ident[:4] == b"\x7fELF" and ident[4] == 2, "Compiled scanner is not a 64-bit ELF file"
assert os.access(scanner, os.X_OK), "Compiled scanner is not executable"

work = tempfile.mkdtemp(prefix="scanner_verify_")
staged = os.path.join(work, "targets")
os.mkdir(staged)
backup = os.path.join(work, "original_targets")

suffix = secrets.token_hex(5)
cases = [
    ("a_ro_" + suffix, 'static const char marker[] __attribute__((used,section(".rodata"))) = "/etc/shadow"; int main(void){return marker[0];}'),
    ("b_data_" + suffix, 'static char marker[] __attribute__((used,section(".data"))) = "/etc/shadow"; int main(void){return marker[0];}'),
    ("c_prefix_" + suffix, 'static const char marker[] __attribute__((used,section(".rodata"))) = "/etc/shadowX"; int main(void){return marker[0];}'),
    ("d_decoy_" + suffix, 'static const char marker[] __attribute__((used,section(".audit_decoy"))) = "/etc/shadow"; int main(void){return marker[0];}'),
    ("e_none_" + suffix, 'int main(void){return 0;}'),
]

try:
    for index, (name, source) in enumerate(cases):
        src = os.path.join(work, name + ".c")
        out = os.path.join(staged, name)
        with open(src, "w") as f:
            f.write(source + "\n")
        subprocess.run(["gcc", "-O0", src, "-o", out], check=True, timeout=20)
        # Exercise both SUID states independently of the finding type.
        os.chmod(out, 0o4755 if index in (0, 2, 4) else 0o755)

    def rodata_contains_exact_shadow(path):
        data = open(path, "rb").read()
        assert data[:4] == b"\x7fELF" and data[4] == 2 and data[5] == 1
        eh = struct.unpack_from("<16sHHIQQQIHHHHHH", data, 0)
        shoff, shentsize, shnum, shstrndx = eh[6], eh[11], eh[12], eh[13]
        assert shentsize >= 64 and shnum > 0 and shstrndx < shnum

        def section_header(i):
            off = shoff + i * shentsize
            assert off + 64 <= len(data)
            return struct.unpack_from("<IIQQQQIIQQ", data, off)

        shstr = section_header(shstrndx)
        string_off, string_size = shstr[4], shstr[5]
        assert string_off + string_size <= len(data)
        names = data[string_off:string_off + string_size]

        for i in range(shnum):
            sh = section_header(i)
            name_off = sh[0]
            if name_off >= len(names):
                continue
            end = names.find(b"\0", name_off)
            if end < 0:
                continue
            if names[name_off:end] == b".rodata":
                sec_off, sec_size = sh[4], sh[5]
                assert sec_off + sec_size <= len(data)
                return b"/etc/shadow\0" in data[sec_off:sec_off + sec_size]
        return False

    expected = []
    for name, _ in cases:
        path = os.path.join(staged, name)
        suid = bool(os.stat(path).st_mode & stat.S_ISUID)
        shadow = rodata_contains_exact_shadow(path)
        expected.append(f"{name}: SUID={'Yes' if suid else 'No'}, SHADOW_IN_RODATA={'Yes' if shadow else 'No'}")
    expected.sort()

    # Sanity-check that the generated corpus distinguishes .rodata from other sections
    # and tests both positive and negative answers.
    assert any("SHADOW_IN_RODATA=Yes" in line for line in expected)
    assert any("SHADOW_IN_RODATA=No" in line for line in expected)
    assert any("SUID=Yes" in line for line in expected)
    assert any("SUID=No" in line for line in expected)

    os.rename(targets, backup)
    os.rename(staged, targets)
    if os.path.exists(results):
        os.remove(results)

    completed = subprocess.run([scanner], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, timeout=20)
    assert completed.returncode == 0, "Scanner failed: " + completed.stderr
    assert os.path.isfile(results), "Scanner did not generate /home/user/scan_results.txt"
    with open(results, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"Behavioral scan mismatch. Expected {expected}, got {actual}"
finally:
    if os.path.isdir(targets) and os.path.isdir(backup):
        shutil.rmtree(targets)
        os.rename(backup, targets)
    elif os.path.isdir(backup) and not os.path.exists(targets):
        os.rename(backup, targets)
    shutil.rmtree(work, ignore_errors=True)
PY_EOF
}

if verify 2>&1; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
fi
