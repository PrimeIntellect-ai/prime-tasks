#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

BUILD_DIR = "/home/user/build_env"
BUILD_PY = os.path.join(BUILD_DIR, "build.py")
LINK_ORDER = os.path.join(BUILD_DIR, "link_order.txt")
ARTIFACT = os.path.join(BUILD_DIR, "build_artifact.bin")

EXPECTED_PATCH = '''--- build.py
+++ build.py
@@ -3,8 +3,22 @@

 def main():
+    parser = argparse.ArgumentParser()
+    parser.add_argument("--link-order", required=True, help="Path to link order file")
+    args = parser.parse_args()
+
     print("Building project...")
-    # Linker fails without correct order
-    raise Exception("Linking failed: Undefined reference in module 'main'.")
+    
+    with open(args.link_order, 'r') as f:
+        order = [line.strip() for line in f if line.strip()]
+        
+    with open("build_artifact.bin", "w") as f:
+        f.write("SUCCESS: " + ",".join(order) + "\\n")
+    print("Build successful!")

 if __name__ == "__main__":
     main()
'''

EXPECTED_ORDER = [
    "libauth_stub",
    "libfs",
    "libdb",
    "libauth",
    "libnet",
    "libcrypto",
    "libhttp",
    "main",
]
EXPECTED_CONTENT = "SUCCESS: " + ",".join(EXPECTED_ORDER)


def test_build_py_patched():
    path = BUILD_PY
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "--link-order" in content, "build.py was not patched correctly (missing --link-order argument)."
    assert "build_artifact.bin" in content, "build.py was not patched correctly (missing artifact generation)."

    result = subprocess.run(
        ["patch", "--dry-run", "--reverse", "--batch", "-p0"],
        cwd=BUILD_DIR,
        input=EXPECTED_PATCH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert result.returncode == 0, (
        "build.py does not contain the changes from fix_linker.patch.\n" + result.stdout
    )


def test_link_order_txt():
    path = LINK_ORDER
    assert os.path.isfile(path), f"File {path} is missing. Did you save the computed build sequence?"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_order = EXPECTED_ORDER
    assert lines == expected_order, f"The build sequence in link_order.txt is incorrect.\nExpected: {expected_order}\nGot: {lines}"


def test_build_py_processes_supplied_order():
    tokens = ["module_" + secrets.token_hex(8) for _ in range(5)]
    with tempfile.TemporaryDirectory() as workdir:
        order_path = os.path.join(workdir, "dynamic_order.txt")
        with open(order_path, "w") as f:
            f.write("\n".join(tokens) + "\n")

        result = subprocess.run(
            ["python3", BUILD_PY, "--link-order", order_path],
            cwd=workdir,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
        )
        assert result.returncode == 0, f"Patched build.py failed when executed:\n{result.stdout}"

        generated = os.path.join(workdir, "build_artifact.bin")
        assert os.path.isfile(generated), "Executing build.py did not generate build_artifact.bin."
        with open(generated, "r") as f:
            content = f.read().strip()
        expected = "SUCCESS: " + ",".join(tokens)
        assert content == expected, f"build.py did not use the supplied link-order file.\nExpected: {expected}\nGot: {content}"


def test_run_required_build():
    if os.path.exists(ARTIFACT):
        os.remove(ARTIFACT)

    result = subprocess.run(
        ["python3", BUILD_PY, "--link-order", LINK_ORDER],
        cwd=BUILD_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert result.returncode == 0, f"The required build command failed:\n{result.stdout}"
    assert os.path.isfile(ARTIFACT), "The required build command did not generate build_artifact.bin."


def test_build_artifact_bin():
    path = ARTIFACT
    assert os.path.isfile(path), f"File {path} is missing. Did you run the patched build script?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = EXPECTED_CONTENT
    assert content == expected_content, f"The content of build_artifact.bin is incorrect.\nExpected: {expected_content}\nGot: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
