#!/bin/bash
mkdir -p /logs/verifier

WORKDIR=$(mktemp -d)
cp -a /home/user/main.c "$WORKDIR/main.c"
cp -a /home/user/libmath.so "$WORKDIR/libmath.so"

cleanup() {
    cp -a "$WORKDIR/main.c" /home/user/main.c 2>/dev/null || true
    cp -a "$WORKDIR/libmath.so" /home/user/libmath.so 2>/dev/null || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

cat << 'PY_EOF' > "$WORKDIR/validate_artifacts.py"
import os
import re
import subprocess
import sys

expected = sys.argv[1]
script = "/home/user/fix_link.py"
bridge = "/home/user/bridge.s"
app = "/home/user/app"
log = "/home/user/test_output.log"
lib = "/home/user/libmath.so"

assert os.path.isfile(script), f"Expected script not found at {script}"
assert os.path.getsize(script) > 0, "fix_link.py is empty"
assert os.path.isfile(bridge), f"Expected assembly file not found at {bridge}"
assert os.path.isfile(app), f"Expected executable not found at {app}"
assert os.access(app, os.X_OK), f"File at {app} is not executable"
assert open(app, "rb").read(4) == b"\x7fELF", "app is not an ELF executable"
assert os.path.isfile(log), f"Expected log file not found at {log}"
with open(log, "r") as f:
    assert f.read() == expected, "test_output.log does not exactly match app's expected output"

run = subprocess.run([app], capture_output=True, text=True, timeout=10)
assert run.returncode == 0, f"app failed: {run.stderr}"
assert run.stdout == expected, f"app output was {run.stdout!r}, expected {expected!r}"

# Derive the required C++ target from the library rather than trusting the submission.
nm_lib = subprocess.run(
    ["nm", "-D", "--defined-only", lib], capture_output=True, text=True, check=True
).stdout
mangled = []
for line in nm_lib.splitlines():
    fields = line.split()
    if not fields:
        continue
    symbol = fields[-1]
    demangled = subprocess.run(
        ["c++filt", symbol], capture_output=True, text=True, check=True
    ).stdout.strip()
    if demangled == "calculate(int, int)":
        mangled.append(symbol)
assert len(mangled) == 1, f"Expected one calculate(int, int) export, found {mangled}"
target = mangled[0]

# Assemble the submitted bridge independently and inspect what it actually defines.
bridge_obj = os.path.join(os.path.dirname(__file__), "bridge-check.o")
subprocess.run(["gcc", "-c", bridge, "-o", bridge_obj], capture_output=True, text=True, check=True)
header = subprocess.run(["readelf", "-h", bridge_obj], capture_output=True, text=True, check=True).stdout
assert "Machine:" in header and "X86-64" in header, "bridge.s is not x86_64 assembly"
defined = subprocess.run(
    ["nm", "-g", "--defined-only", bridge_obj], capture_output=True, text=True, check=True
).stdout
assert re.search(r"\b[Tt]\s+calculate$", defined, re.M), "bridge.s does not globally define calculate"
undefined = subprocess.run(["nm", "-u", bridge_obj], capture_output=True, text=True, check=True).stdout
assert re.search(rf"\b{re.escape(target)}$", undefined, re.M), "bridge does not reference the discovered C++ symbol"
bridge_dis = subprocess.run(["objdump", "-d", bridge_obj], capture_output=True, text=True, check=True).stdout
assert re.search(r"<calculate>:\n(?:.*\n){0,8}.*\bjmp\w*\b", bridge_dis), "calculate is not a jump trampoline"

# Verify that app is a real linked executable using libmath.so and an appropriate runtime path.
dyn = subprocess.run(["readelf", "-d", app], capture_output=True, text=True, check=True).stdout
assert re.search(r"\(NEEDED\).*\[libmath\.so\]", dyn), "app is not dynamically linked against libmath.so"
rpaths = re.findall(r"\((?:RUNPATH|RPATH)\).*\[(.*?)\]", dyn)
assert any("/home/user" in p or "$ORIGIN" in p for p in rpaths), "app lacks a usable rpath for /home/user/libmath.so"
ldd = subprocess.run(["ldd", app], capture_output=True, text=True, check=True).stdout
assert re.search(r"libmath\.so\s+=>\s+/home/user/libmath\.so", ldd), "app does not resolve the required library from /home/user"

symbols = subprocess.run(["nm", "-g", app], capture_output=True, text=True, check=True).stdout
assert re.search(r"\b[Tt]\s+calculate$", symbols, re.M), "app does not contain the bridge calculate symbol"
app_dis = subprocess.run(["objdump", "-d", app], capture_output=True, text=True, check=True).stdout
lines = app_dis.splitlines()

def function_body(name):
    start = next((i for i, line in enumerate(lines) if re.search(rf"<{re.escape(name)}>:$", line)), None)
    assert start is not None, f"No disassembly for {name}"
    body = []
    for line in lines[start + 1:]:
        if re.search(r"^[0-9a-fA-F]+\s+<[^>]+>:$", line):
            break
        body.append(line)
    return "\n".join(body)

calc_body = function_body("calculate")
assert re.search(r"\bjmp\w*\b", calc_body), "linked calculate implementation is not a trampoline"
assert target in calc_body, "linked calculate trampoline does not jump to the discovered symbol"
main_body = function_body("main")
assert re.search(r"\bcall\w*\b.*<calculate>", main_body), "app's main does not call the bridge calculate symbol"
PY_EOF

cat << 'PY_EOF' > "$WORKDIR/test_final_state.py"
import os
import subprocess
import pytest

def test_fix_link_script_exists():
    script_path = "/home/user/fix_link.py"
    assert os.path.isfile(script_path), f"Expected script not found at {script_path}"

def test_bridge_assembly_exists():
    bridge_path = "/home/user/bridge.s"
    assert os.path.isfile(bridge_path), f"Expected assembly file not found at {bridge_path}"

def test_app_executable_exists():
    app_path = "/home/user/app"
    assert os.path.isfile(app_path), f"Expected executable not found at {app_path}"
    assert os.access(app_path, os.X_OK), f"File at {app_path} is not executable"

def test_output_log_content():
    log_path = "/home/user/test_output.log"
    assert os.path.isfile(log_path), f"Expected log file not found at {log_path}"
    with open(log_path, "r") as f:
        content = f.read()
    expected_output = "Result: 11\n"
    assert content == expected_output, f"Log file content is incorrect. Expected {expected_output!r}, got {content!r}"

def test_app_runs_correctly():
    app_path = "/home/user/app"
    try:
        result = subprocess.run([app_path], capture_output=True, text=True, check=True, timeout=10)
        assert result.stdout == "Result: 11\n", f"App output is incorrect. Expected 'Result: 11\\n', got {result.stdout!r}"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Executing {app_path} failed with return code {e.returncode} and stderr: {e.stderr}")
    except OSError as e:
        pytest.fail(f"Failed to execute {app_path}: {e}")
PY_EOF

if (
    set -e

    # First run against verifier-generated inputs. This proves the script rebuilds
    # from main.c and links the supplied shared library instead of preserving fakes.
    python3 - "$WORKDIR" << 'PY_EOF'
import secrets
import sys
from pathlib import Path

work = Path(sys.argv[1])
a = secrets.randbelow(30) + 9
b = secrets.randbelow(30) + 7
p = secrets.randbelow(5) + 2
q = secrets.randbelow(7) + 3
c = secrets.randbelow(19) + 1
marker = "Probe_" + secrets.token_hex(8)
(work / "probe.cpp").write_text(
    f"int calculate(int a, int b) {{ return a * {p} + b * {q} + {c}; }}\n"
)
Path("/home/user/main.c").write_text(
    "#include <stdio.h>\n"
    "int calculate(int a, int b);\n"
    f"int main(void) {{ printf(\"{marker}: %d\\n\", calculate({a}, {b})); return 0; }}\n"
)
(work / "probe_expected").write_text(f"{marker}: {a*p + b*q + c}\n")
PY_EOF
    g++ -fPIC -shared -o /home/user/libmath.so "$WORKDIR/probe.cpp"
    probe_main_hash=$(sha256sum /home/user/main.c | awk '{print $1}')
    probe_lib_hash=$(sha256sum /home/user/libmath.so | awk '{print $1}')
    rm -f /home/user/bridge.s /home/user/app /home/user/test_output.log
    timeout 30s python3 /home/user/fix_link.py
    test "$probe_main_hash" = "$(sha256sum /home/user/main.c | awk '{print $1}')"
    test "$probe_lib_hash" = "$(sha256sum /home/user/libmath.so | awk '{print $1}')"
    python3 "$WORKDIR/validate_artifacts.py" "$(cat "$WORKDIR/probe_expected")"

    # Restore the specified task inputs and require a clean end-to-end final run.
    cp -a "$WORKDIR/main.c" /home/user/main.c
    cp -a "$WORKDIR/libmath.so" /home/user/libmath.so
    grep -Fq 'printf("Result: %d\\n", calculate(5, 3));' /home/user/main.c
    final_main_hash=$(sha256sum /home/user/main.c | awk '{print $1}')
    final_lib_hash=$(sha256sum /home/user/libmath.so | awk '{print $1}')
    rm -f /home/user/bridge.s /home/user/app /home/user/test_output.log
    timeout 30s python3 /home/user/fix_link.py
    test "$final_main_hash" = "$(sha256sum /home/user/main.c | awk '{print $1}')"
    test "$final_lib_hash" = "$(sha256sum /home/user/libmath.so | awk '{print $1}')"
    python3 "$WORKDIR/validate_artifacts.py" $'Result: 11\n'
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$WORKDIR/test_final_state.py" -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
