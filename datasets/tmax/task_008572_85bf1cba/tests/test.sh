#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import pytest

PROJECT_DIR = "/home/user/project"
BUILD_SH = os.path.join(PROJECT_DIR, "build.sh")
TEST_BUILD_SH = os.path.join(PROJECT_DIR, "test_build.sh")
APP = os.path.join(PROJECT_DIR, "app")
MAIN_C = os.path.join(PROJECT_DIR, "main.c")
UTILS_C = os.path.join(PROJECT_DIR, "utils.c")


def test_test_build_sh_exists_and_executable():
    assert os.path.isfile(TEST_BUILD_SH), f"File {TEST_BUILD_SH} is missing."
    assert os.access(TEST_BUILD_SH, os.X_OK), f"File {TEST_BUILD_SH} is not executable."


def test_test_build_sh_execution():
    # Clean up app if it exists to ensure test_build.sh actually builds it or relies on build.sh
    if os.path.exists(APP):
        os.remove(APP)

    result = subprocess.run(
        [TEST_BUILD_SH],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30
    )
    assert result.returncode == 0, f"{TEST_BUILD_SH} failed with exit code {result.returncode}. Stderr: {result.stderr}"


def test_app_exists_and_executable():
    assert os.path.isfile(APP), f"Executable {APP} is missing. The build script might not have produced it."
    assert os.access(APP, os.X_OK), f"File {APP} is not executable."


def test_app_output():
    # Run the app and check the output
    result = subprocess.run(
        [APP],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10
    )
    assert result.returncode == 0, f"{APP} failed to run with exit code {result.returncode}."
    assert "Build success!" in result.stdout, f"Expected 'Build success!' in output, but got: {result.stdout}"
    assert "Utils module loaded." in result.stdout, f"Expected 'Utils module loaded.' in output, but got: {result.stdout}"


def test_test_build_sh_really_invokes_build_and_checks_app():
    original = open(BUILD_SH, "rb").read()
    original_mode = stat.S_IMODE(os.stat(BUILD_SH).st_mode)
    marker = os.path.join(PROJECT_DIR, ".build_probe_ran")

    for path in (APP, marker):
        if os.path.lexists(path):
            os.remove(path)

    try:
        with open(BUILD_SH, "w") as f:
            f.write("#!/bin/bash\ntouch .build_probe_ran\nexit 0\n")
        os.chmod(BUILD_SH, 0o755)

        result = subprocess.run(
            [TEST_BUILD_SH],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15
        )
        assert os.path.isfile(marker), f"{TEST_BUILD_SH} did not run ./build.sh."
        assert result.returncode == 1, (
            f"{TEST_BUILD_SH} must return 1 when build.sh does not produce an executable app; "
            f"got {result.returncode}."
        )
        assert not os.path.exists(APP), f"{TEST_BUILD_SH} created app itself instead of relying on build.sh."
    finally:
        with open(BUILD_SH, "wb") as f:
            f.write(original)
        os.chmod(BUILD_SH, original_mode)
        if os.path.lexists(marker):
            os.remove(marker)


def test_build_sh_compiles_and_links_both_sources():
    main_original = open(MAIN_C, "rb").read()
    utils_original = open(UTILS_C, "rb").read()
    token = secrets.token_hex(16)
    main_text = "MAIN_" + token
    utils_text = "UTILS_" + token

    try:
        with open(MAIN_C, "w") as f:
            f.write(
                '#include <stdio.h>\n'
                'void utils_func(void);\n'
                'int main(void) {\n'
                '    utils_func();\n'
                f'    printf("{main_text}\\n");\n'
                '    return 0;\n'
                '}\n'
            )
        with open(UTILS_C, "w") as f:
            f.write(
                '#include <stdio.h>\n'
                'void utils_func(void) {\n'
                f'    printf("{utils_text}\\n");\n'
                '}\n'
            )

        # Remove all products that the original two-source build could reuse.
        for name in ("app", "main.o", "utils.o"):
            path = os.path.join(PROJECT_DIR, name)
            if os.path.lexists(path):
                os.remove(path)

        result = subprocess.run(
            [BUILD_SH],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30
        )
        assert result.returncode == 0, (
            f"Running build.sh directly failed with exit code {result.returncode}. "
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert os.path.isfile(APP), "build.sh did not produce app."
        assert os.access(APP, os.X_OK), "The app produced by build.sh is not executable."

        with open(APP, "rb") as f:
            assert f.read(4) == b"\x7fELF", "build.sh did not produce a native compiled executable."

        run = subprocess.run(
            [APP],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10
        )
        assert run.returncode == 0, f"Freshly built app failed: {run.stderr}"
        assert run.stdout.splitlines() == [utils_text, main_text], (
            "The freshly built app does not contain and execute code from both current C sources. "
            f"Got: {run.stdout!r}"
        )

        symbols = subprocess.run(
            ["/usr/bin/nm", APP],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10
        )
        assert symbols.returncode == 0, f"Could not inspect compiled app: {symbols.stderr}"
        assert re.search(r"\bmain$", symbols.stdout, re.MULTILINE), "Compiled app has no main symbol."
        assert re.search(r"\butils_func$", symbols.stdout, re.MULTILINE), (
            "Compiled app is not linked with utils_func from utils.c."
        )
    finally:
        with open(MAIN_C, "wb") as f:
            f.write(main_original)
        with open(UTILS_C, "wb") as f:
            f.write(utils_original)


def test_build_sh_fixed():
    # Ensure build.sh actually links utils.o or compiles correctly
    with open(BUILD_SH, "r") as f:
        content = f.read()
    # It should mention utils.o or utils.c in the gcc command that produces app
    assert "gcc" in content and "app" in content, f"{BUILD_SH} does not seem to compile 'app' anymore."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
