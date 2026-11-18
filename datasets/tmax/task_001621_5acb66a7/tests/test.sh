#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile

PROJECT = "/home/user/signal_project"
AGENT_BIN = os.path.join(PROJECT, "poly_tool_x86_64")


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 60)
    return subprocess.run(cmd, **kwargs)


def assert_elf(path):
    assert os.path.isfile(path), f"Expected executable {path} is missing."
    assert not os.path.islink(path), f"{path} must be a compiled executable, not a symlink."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF executable."


def expected(x):
    return (42 * x**3 + 15 * x**2 + 99 * x) % 1000000007


def test_ci_build_script_exists_and_functions():
    script_path = os.path.join(PROJECT, "ci_build.sh")
    assert os.path.isfile(script_path), f"CI/CD script {script_path} is missing."

    syntax = run(["bash", "-n", script_path])
    assert syntax.returncode == 0, syntax.stderr

    with tempfile.TemporaryDirectory() as fakebin:
        log_path = os.path.join(fakebin, "commands.log")

        def write_wrapper(name, body):
            path = os.path.join(fakebin, name)
            with open(path, "w") as f:
                f.write("#!/bin/bash\n" + body)
            os.chmod(path, 0o755)

        write_wrapper("apt-get", 'printf "apt-get\\t%s\\n" "$*" >> "$CI_TEST_LOG"\nexit 0\n')
        write_wrapper("make", 'printf "make\\t%s\\n" "$*" >> "$CI_TEST_LOG"\nexit 0\n')
        write_wrapper("sudo", 'exec "$@"\n')

        env = os.environ.copy()
        env["CI_TEST_LOG"] = log_path
        env["PATH"] = fakebin + os.pathsep + env.get("PATH", "")
        proc = run(["bash", script_path], cwd=PROJECT, env=env)
        assert proc.returncode == 0, f"ci_build.sh failed: {proc.stderr}"
        assert os.path.isfile(log_path), "ci_build.sh did not invoke apt-get or make."

        with open(log_path) as f:
            commands = f.read().splitlines()

        apt_installs = [line for line in commands if line.startswith("apt-get\t") and re.search(r"\binstall\b", line)]
        assert any(re.search(r"\bgcc-aarch64-linux-gnu\b", line) for line in apt_installs), (
            "ci_build.sh must install gcc-aarch64-linux-gnu via apt-get."
        )

        make_calls = [line.split("\t", 1)[1] for line in commands if line.startswith("make\t")]
        assert any(re.search(r"(^|\s)ARCH=x86_64($|\s)", args) for args in make_calls), (
            "ci_build.sh must build with ARCH=x86_64."
        )
        assert any(re.search(r"(^|\s)ARCH=aarch64($|\s)", args) for args in make_calls), (
            "ci_build.sh must build with ARCH=aarch64."
        )


def test_source_contains_extracted_coefficients():
    source_path = os.path.join(PROJECT, "poly_filter.c")
    assert os.path.isfile(source_path), f"Source file {source_path} is missing."
    source = open(source_path).read()
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//.*", "", source)

    for name, value in (("c1", 42), ("c2", 15), ("c3", 99)):
        pattern = rf"\b{name}\s*=\s*{value}(?:[uUlL]*)\b"
        assert re.search(pattern, source), f"poly_filter.c does not initialize {name} to {value}."


def test_makefile_architecture_selection_and_linking():
    with tempfile.TemporaryDirectory() as build_dir:
        for name in ("main.c", "poly_filter.c", "poly_filter.h", "Makefile"):
            shutil.copy2(os.path.join(PROJECT, name), os.path.join(build_dir, name))

        def clear_build_products():
            for name in os.listdir(build_dir):
                if name.endswith(".o") or name.startswith("poly_tool"):
                    os.remove(os.path.join(build_dir, name))

        clear_build_products()
        proc = run(["make"], cwd=build_dir)
        assert proc.returncode == 0, f"Default x86_64 build failed:\n{proc.stdout}\n{proc.stderr}"
        assert_elf(os.path.join(build_dir, "poly_tool_x86_64"))

        clear_build_products()
        proc = run(["make", "ARCH=x86_64"], cwd=build_dir)
        assert proc.returncode == 0, f"ARCH=x86_64 build failed:\n{proc.stdout}\n{proc.stderr}"
        assert_elf(os.path.join(build_dir, "poly_tool_x86_64"))

        clear_build_products()
        with tempfile.TemporaryDirectory() as fakebin:
            compiler_log = os.path.join(fakebin, "compiler.log")
            compiler = os.path.join(fakebin, "aarch64-linux-gnu-gcc")
            with open(compiler, "w") as f:
                f.write("#!/bin/bash\n")
                f.write('echo invoked >> "$AARCH64_COMPILER_LOG"\n')
                f.write('exec /usr/bin/gcc "$@"\n')
            os.chmod(compiler, 0o755)

            env = os.environ.copy()
            env["PATH"] = fakebin + os.pathsep + env.get("PATH", "")
            env["AARCH64_COMPILER_LOG"] = compiler_log
            proc = run(["make", "ARCH=aarch64"], cwd=build_dir, env=env)
            assert proc.returncode == 0, f"ARCH=aarch64 build failed:\n{proc.stdout}\n{proc.stderr}"
            assert os.path.isfile(compiler_log), "ARCH=aarch64 did not select aarch64-linux-gnu-gcc."
            assert_elf(os.path.join(build_dir, "poly_tool_aarch64"))


def test_agent_binary_exists():
    assert_elf(AGENT_BIN)


def test_fuzz_equivalence():
    assert_elf(AGENT_BIN)
    random.seed(42)
    inputs = [random.randint(0, 50000) for _ in range(1000)]

    for val in inputs:
        proc = run([AGENT_BIN, str(val)], timeout=5)
        assert proc.returncode == 0, f"Agent binary failed on input {val}: {proc.stderr}"
        output = proc.stdout.strip()
        assert output == str(expected(val)), (
            f"Output mismatch on input {val}. Expected {expected(val)}, got {output!r}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
