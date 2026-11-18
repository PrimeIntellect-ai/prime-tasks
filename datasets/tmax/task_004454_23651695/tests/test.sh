#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import stat
import subprocess
import tempfile
import uuid

import pytest

PROJECT_DIR = "/home/user/project"


def smallest_matching_prime():
    def is_prime(n):
        if n < 2:
            return False
        d = 2
        while d * d <= n:
            if n % d == 0:
                return False
            d += 1
        return True

    for value in range(1000, 10000):
        if value % 7 == 3 and value % 13 == 5 and is_prime(value):
            return value
    raise AssertionError("No matching prime found")


def expected_metadata():
    output = []
    paths = sorted(glob.glob(os.path.join(PROJECT_DIR, "*.c")) +
                   glob.glob(os.path.join(PROJECT_DIR, "*.h")))
    for path in paths:
        tags = []
        with open(path, "r") as source:
            for line in source:
                if "// META:" in line:
                    parts = line.strip().split("// META:")[1].strip().split(":")
                    if len(parts) == 2:
                        tags.append((parts[0].strip(), parts[1].strip()))
        output.append(f"FILE: {os.path.basename(path)}\n")
        output.append(f"TAGS: {len(tags)}\n")
        for key, value in tags:
            output.append(f"{key}={value}\n")
    return "".join(output)


def run_serializer():
    script = os.path.join(PROJECT_DIR, "serialize_meta.sh")
    metadata = os.path.join(PROJECT_DIR, "metadata.txt")
    if os.path.exists(metadata):
        os.unlink(metadata)

    with tempfile.TemporaryDirectory() as deny_dir:
        for command in ("python", "python2", "python3", "perl", "ruby"):
            wrapper = os.path.join(deny_dir, command)
            with open(wrapper, "w") as f:
                f.write("#!/bin/sh\necho 'forbidden interpreter invoked' >&2\nexit 97\n")
            os.chmod(wrapper, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)

        env = os.environ.copy()
        env["PATH"] = deny_dir + os.pathsep + env.get("PATH", "")
        result = subprocess.run(
            ["/bin/bash", script], cwd=PROJECT_DIR, env=env,
            capture_output=True, text=True, timeout=20
        )

    assert result.returncode == 0, (
        f"serialize_meta.sh failed with return code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(metadata), "serialize_meta.sh did not generate metadata.txt"


def test_makefile_builds_app_from_scratch_with_required_macro():
    expected_secret = smallest_matching_prime()
    assert expected_secret == 1123

    dry_run = subprocess.run(
        ["make", "-nB", "app"], cwd=PROJECT_DIR,
        capture_output=True, text=True, timeout=20
    )
    assert dry_run.returncode == 0, f"make dry run failed:\n{dry_run.stdout}\n{dry_run.stderr}"
    commands = dry_run.stdout + dry_run.stderr
    assert re.search(r"-D\s*SECRET_ID\s*=\s*1123\b", commands), (
        "The Makefile's expanded build commands do not pass -DSECRET_ID=1123"
    )
    assert "main.c" in commands and "utils.c" in commands and "-c" in commands, (
        "The Makefile does not contain expanded commands compiling the project C sources"
    )

    for path in glob.glob(os.path.join(PROJECT_DIR, "*.o")):
        os.unlink(path)
    app_path = os.path.join(PROJECT_DIR, "app")
    if os.path.lexists(app_path):
        os.unlink(app_path)

    build = subprocess.run(
        ["make", "app"], cwd=PROJECT_DIR,
        capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(app_path), "make did not create app"
    with open(app_path, "rb") as app_file:
        assert app_file.read(4) == b"\x7fELF", "app is not a compiled ELF executable"


def test_app_compiled_and_executable():
    app_path = os.path.join(PROJECT_DIR, "app")
    assert os.path.isfile(app_path), f"Executable {app_path} does not exist."
    assert os.access(app_path, os.X_OK), f"File {app_path} is not executable."


def test_app_output():
    app_path = os.path.join(PROJECT_DIR, "app")
    try:
        result = subprocess.run([app_path], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running {app_path} failed with return code {e.returncode} and output: {e.output}")

    expected_output = "Secret: 1123\nUtils loaded.\n"
    assert result.stdout == expected_output, f"App output did not match expected.\nExpected:\n{expected_output}\nGot:\n{result.stdout}"


def test_bash_script_exists():
    sh_script = os.path.join(PROJECT_DIR, "serialize_meta.sh")
    assert os.path.isfile(sh_script), f"Bash script {sh_script} does not exist."

    with open(sh_script, "r") as f:
        lines = f.readlines()
    active_text = "\n".join(line.split("#", 1)[0] for line in lines if not line.startswith("#!"))
    assert not re.search(r"\b(?:python(?:[0-9.]+)?|perl|ruby)\b", active_text, re.IGNORECASE), (
        "serialize_meta.sh references a forbidden interpreter"
    )


def test_serializer_generates_original_metadata():
    run_serializer()


def test_metadata_output():
    metadata_path = os.path.join(PROJECT_DIR, "metadata.txt")
    assert os.path.isfile(metadata_path), f"Metadata file {metadata_path} does not exist."

    expected_content = (
        "FILE: main.c\n"
        "TAGS: 2\n"
        "author=alice\n"
        "version=1.2\n"
        "FILE: utils.c\n"
        "TAGS: 2\n"
        "module=utils\n"
        "status=stable\n"
        "FILE: utils.h\n"
        "TAGS: 0\n"
    )

    with open(metadata_path, "r") as f:
        content = f.read()

    assert content == expected_content, f"Content of {metadata_path} did not match expected.\nExpected:\n{expected_content}\nGot:\n{content}"


def test_serializer_handles_derived_dynamic_input():
    token = uuid.uuid4().hex
    extra_c = os.path.join(PROJECT_DIR, f"audit_{token}.c")
    extra_h = os.path.join(PROJECT_DIR, f"audit_{token}.h")
    metadata_path = os.path.join(PROJECT_DIR, "metadata.txt")

    try:
        with open(extra_c, "w") as f:
            f.write(
                "// META: generated:yes\n"
                "int audit_value = 1; // META: inline : accepted\n"
                "// META: too:many:fields\n"
                "// META: empty:\n"
            )
        with open(extra_h, "w") as f:
            f.write("#ifndef AUDIT_H\n#define AUDIT_H\n// META: kind:header\n#endif\n")

        expected = expected_metadata()
        run_serializer()
        with open(metadata_path, "r") as f:
            actual = f.read()
        assert actual == expected, (
            "serialize_meta.sh did not reproduce the required serialization for dynamic C/H inputs.\n"
            f"Expected:\n{expected}\nGot:\n{actual}"
        )
    finally:
        for path in (extra_c, extra_h):
            if os.path.exists(path):
                os.unlink(path)
        run_serializer()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
