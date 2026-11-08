#!/bin/bash
set -e
mkdir -p /logs/verifier

# Restore the supplied project to its pristine state and remove any prebuilt
# artifacts so the submitted script must perform the repair and build itself.
rm -rf /home/user/project/main /home/user/project/liba.so /home/user/project/libb.so
rm -f /home/user/project/a.c /home/user/project/a.h \
      /home/user/project/b.c /home/user/project/b.h \
      /home/user/project/main.c /home/user/project/fix.patch

cat > /home/user/project/a.h <<'EOF'
#ifndef A_H
#define A_H
int func_a();
#endif
EOF
cat > /home/user/project/a.c <<'EOF'
#include "b.h"
int func_a() {
    return func_b() + 10;
}
EOF
cat > /home/user/project/b.h <<'EOF'
#ifndef B_H
#define B_H
int func_b();
#endif
EOF
cat > /home/user/project/b.c <<'EOF'
#include "a.h"
int func_b() {
    return func_a() + 20;
}
EOF
cat > /home/user/project/main.c <<'EOF'
#include <stdio.h>
#include "a.h"

int main() {
    printf("Result: %d\n", func_a());
    return 0;
}
EOF
python3 - <<'PY'
patch = '''--- b.c
+++ b.c
@@ -1,4 +1,4 @@
 #include "a.h"
 int func_b() {
-    return func_a() + 20;
+    return 42;
 }
'''
with open('/home/user/project/fix.patch', 'wb') as f:
    f.write(patch.encode('utf-16le'))
PY
chown user:user /home/user/project/a.c /home/user/project/a.h \
                /home/user/project/b.c /home/user/project/b.h \
                /home/user/project/main.c /home/user/project/fix.patch
chmod 666 /home/user/project/a.c /home/user/project/a.h \
          /home/user/project/b.c /home/user/project/b.h \
          /home/user/project/main.c /home/user/project/fix.patch

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import pytest

PROJECT = "/home/user/project"


def run_tool(args):
    return subprocess.run(args, capture_output=True, text=True)


def assert_elf(path, allowed_types):
    assert os.path.isfile(path), f"Required build artifact {path} was not created."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF file."
    result = run_tool(["readelf", "-h", path])
    assert result.returncode == 0, f"Failed to inspect ELF header for {path}: {result.stderr}"
    match = re.search(r"^\s*Type:\s+(\S+)", result.stdout, re.MULTILINE)
    assert match and match.group(1) in allowed_types, f"{path} has the wrong ELF type."


def dynamic_needed(path):
    result = run_tool(["readelf", "-d", path])
    assert result.returncode == 0, f"Failed to inspect dynamic section of {path}: {result.stderr}"
    return set(re.findall(r"\(NEEDED\).*?\[([^]]+)\]", result.stdout))


def symbol_states(path, symbol):
    result = run_tool(["readelf", "-Ws", path])
    assert result.returncode == 0, f"Failed to inspect symbols in {path}: {result.stderr}"
    states = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 8 and fields[-1].split("@", 1)[0] == symbol:
            states.append(fields[6])
    return states


def test_build_script_exists_and_executable():
    script_path = "/home/user/build.sh"
    assert os.path.isfile(script_path), f"Build script {script_path} does not exist."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"Build script {script_path} is not executable."


def test_build_script_execution_and_output():
    # Execute the build script as the user against the restored UTF-16LE patch.
    build_result = subprocess.run(
        ["su", "-", "user", "-c", "/home/user/build.sh"],
        capture_output=True,
        text=True
    )
    assert build_result.returncode == 0, f"Build script failed to execute properly. Stderr: {build_result.stderr}"

    main_path = "/home/user/project/main"
    assert os.path.isfile(main_path), f"Executable {main_path} was not created."
    assert os.access(main_path, os.X_OK), f"File {main_path} is not executable."

    # The supplied patch must have actually repaired b.c.
    with open("/home/user/project/b.c", encoding="utf-8") as f:
        repaired_b = f.read()
    assert "return 42;" in repaired_b, "The UTF-16LE patch was not applied to b.c."
    assert "return func_a() + 20;" not in repaired_b, "The circular call remains in b.c."

    liba = "/home/user/project/liba.so"
    libb = "/home/user/project/libb.so"
    assert_elf(liba, {"DYN"})
    assert_elf(libb, {"DYN"})
    assert_elf(main_path, {"EXEC", "DYN"})

    # Verify that these are the requested cooperating libraries, rather than
    # dummy files accompanying a standalone constant-output executable.
    assert any(s != "UND" for s in symbol_states(liba, "func_a")), "liba.so does not define func_a."
    assert "UND" in symbol_states(liba, "func_b"), "liba.so does not call func_b from libb.so."
    assert any(s != "UND" for s in symbol_states(libb, "func_b")), "libb.so does not define func_b."
    assert "UND" not in symbol_states(libb, "func_a"), "libb.so still depends on func_a."
    assert "UND" in symbol_states(main_path, "func_a"), "main is not dynamically linked to func_a."

    needed = dynamic_needed(main_path)
    assert "liba.so" in needed, "main does not dynamically link against liba.so."
    assert "libb.so" in needed, "main does not dynamically link against libb.so."

    # Execute the compiled binary in a clean environment (no LD_LIBRARY_PATH).
    run_result = subprocess.run(
        ["su", "-", "user", "-c", "/home/user/project/main"],
        capture_output=True,
        text=True
    )
    assert run_result.returncode == 0, f"Running main failed. It may not be finding the shared libraries. Stderr: {run_result.stderr}"
    assert run_result.stdout.strip() == "Result: 52", f"Expected output 'Result: 52', but got: '{run_result.stdout.strip()}'"

    # Confirm that runtime resolution selects the libraries built in the project.
    ldd_result = subprocess.run(
        ["su", "-", "user", "-c", "ldd /home/user/project/main"],
        capture_output=True,
        text=True
    )
    assert ldd_result.returncode == 0, f"Failed to inspect runtime library resolution: {ldd_result.stderr}"
    for name in ("liba.so", "libb.so"):
        match = re.search(rf"^\s*{re.escape(name)}\s+=>\s+(\S+)", ldd_result.stdout, re.MULTILINE)
        assert match, f"{name} was not resolved at runtime."
        assert os.path.realpath(match.group(1)) == os.path.realpath(os.path.join(PROJECT, name)), \
            f"{name} did not resolve to the library in {PROJECT}."


def test_rpath_configured():
    main_path = "/home/user/project/main"
    if not os.path.isfile(main_path):
        pytest.fail(f"Executable {main_path} not found, cannot check rpath.")

    result = subprocess.run(["readelf", "-d", main_path], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run readelf to inspect the binary."

    has_correct_rpath = False
    for line in result.stdout.splitlines():
        if "(RPATH)" in line or "(RUNPATH)" in line:
            if "/home/user/project" in line or "$ORIGIN" in line:
                has_correct_rpath = True
                break

    assert has_correct_rpath, "RPATH or RUNPATH is not correctly set to /home/user/project or $ORIGIN in the main executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
