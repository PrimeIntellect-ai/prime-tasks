#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess

import pytest

BASE_DIR = "/home/user/build_system"


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="") as f:
        f.write(content)


def run_make(*args):
    return subprocess.run(
        [os.path.join(BASE_DIR, "make.sh"), *args],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def reset_original_fixture():
    shutil.rmtree(os.path.join(BASE_DIR, "src"), ignore_errors=True)
    shutil.rmtree(os.path.join(BASE_DIR, "patches"), ignore_errors=True)
    shutil.rmtree(os.path.join(BASE_DIR, "out"), ignore_errors=True)
    os.makedirs(os.path.join(BASE_DIR, "src"))
    os.makedirs(os.path.join(BASE_DIR, "patches"))
    os.makedirs(os.path.join(BASE_DIR, "out"))

    write(os.path.join(BASE_DIR, "graph.txt"), "A: B C\nB: D\nC: D\nD: \n")
    for name in "ABCD":
        write(os.path.join(BASE_DIR, "src", name + ".txt"), f"Source {name}\n")
    write(os.path.join(BASE_DIR, "patches", "B.patch"),
          "--- src/B.txt\n+++ src/B.txt\n@@ -1 +1 @@\n-Source B\n+Source B Patched\n")
    write(os.path.join(BASE_DIR, "patches", "D.patch"),
          "--- src/D.txt\n+++ src/D.txt\n@@ -1 +1 @@\n-Source D\n+Source D Patched\n")
    try:
        os.remove(os.path.join(BASE_DIR, "final_output.log"))
    except FileNotFoundError:
        pass


@pytest.fixture(scope="module", autouse=True)
def build_original_state():
    make_sh = os.path.join(BASE_DIR, "make.sh")
    assert os.path.isfile(make_sh), f"{make_sh} does not exist."
    assert os.access(make_sh, os.X_OK), f"{make_sh} is not executable."
    reset_original_fixture()
    result = run_make("A")
    assert result.returncode == 0, (
        f"make.sh A failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    yield


def test_make_sh_exists_and_executable():
    make_sh = os.path.join(BASE_DIR, "make.sh")
    assert os.path.isfile(make_sh), f"{make_sh} does not exist."
    assert os.access(make_sh, os.X_OK), f"{make_sh} is not executable."


def test_final_output_log():
    log_path = os.path.join(BASE_DIR, "final_output.log")
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected = "Source D Patched\nSource B Patched\nSource D Patched\nSource C\nSource A"
    assert content == expected, f"final_output.log content is incorrect.\nGot:\n{content}\nExpected:\n{expected}"


def test_out_a_matches_log():
    out_a = os.path.join(BASE_DIR, "out", "A.out")
    log_path = os.path.join(BASE_DIR, "final_output.log")

    assert os.path.isfile(out_a), f"{out_a} does not exist."
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(out_a, "r") as f1, open(log_path, "r") as f2:
        assert f1.read().strip() == f2.read().strip(), "out/A.out content does not match final_output.log"


def test_patched_sources():
    b_txt = os.path.join(BASE_DIR, "src", "B.txt")
    d_txt = os.path.join(BASE_DIR, "src", "D.txt")

    with open(b_txt, "r") as f:
        assert f.read().strip() == "Source B Patched", "src/B.txt was not correctly patched."

    with open(d_txt, "r") as f:
        assert f.read().strip() == "Source D Patched", "src/D.txt was not correctly patched."


def test_unpatched_sources_unchanged():
    a_txt = os.path.join(BASE_DIR, "src", "A.txt")
    c_txt = os.path.join(BASE_DIR, "src", "C.txt")

    with open(a_txt, "r") as f:
        assert f.read().strip() == "Source A", "src/A.txt should not have been modified."

    with open(c_txt, "r") as f:
        assert f.read().strip() == "Source C", "src/C.txt should not have been modified."


def test_dynamic_execution_dependency_arguments_rebuild_and_idempotence():
    token = secrets.token_hex(12)
    deps = {
        "A": ["C", "B"],
        "B": ["D"],
        "C": ["E", "D"],
        "D": [],
        "E": [],
    }
    original = {name: f"{token}-{name}-source\n" for name in deps}
    patched = dict(original)
    patched["B"] = f"{token}-B-patched\n"
    patched["D"] = f"{token}-D-patched\n"

    shutil.rmtree(os.path.join(BASE_DIR, "src"), ignore_errors=True)
    shutil.rmtree(os.path.join(BASE_DIR, "patches"), ignore_errors=True)
    shutil.rmtree(os.path.join(BASE_DIR, "out"), ignore_errors=True)
    os.makedirs(os.path.join(BASE_DIR, "src"))
    os.makedirs(os.path.join(BASE_DIR, "patches"))
    os.makedirs(os.path.join(BASE_DIR, "out"))

    write(os.path.join(BASE_DIR, "graph.txt"),
          "A: C B\nB: D\nC: E D\nD: \nE: \n")
    for name, content in original.items():
        write(os.path.join(BASE_DIR, "src", name + ".txt"), content)
    for name in ("B", "D"):
        write(os.path.join(BASE_DIR, "patches", name + ".patch"),
              f"--- src/{name}.txt\n+++ src/{name}.txt\n@@ -1 +1 @@\n"
              f"-{original[name].rstrip(chr(10))}\n+{patched[name].rstrip(chr(10))}\n")

    # Leave A.out only so implementations that always refresh final_output.log can
    # still run a non-A target; no dependency output is precomputed.
    write(os.path.join(BASE_DIR, "out", "A.out"), f"{token}-sentinel\n")
    result = run_make("B")
    assert result.returncode == 0, (
        f"make.sh B failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(os.path.join(BASE_DIR, "out", "B.out"))
    assert os.path.isfile(os.path.join(BASE_DIR, "out", "D.out"))
    assert not os.path.exists(os.path.join(BASE_DIR, "out", "C.out")), "C must not be built for target B"
    assert not os.path.exists(os.path.join(BASE_DIR, "out", "E.out")), "E must not be built for target B"
    with open(os.path.join(BASE_DIR, "out", "B.out"), "r") as f:
        assert f.read() == patched["D"] + patched["B"]

    shutil.rmtree(os.path.join(BASE_DIR, "out"))
    os.makedirs(os.path.join(BASE_DIR, "out"))

    def expected(name, sources):
        if not deps[name]:
            return sources[name]
        data = ""
        for dep in sorted(deps[name]):
            part = expected(dep, sources)
            data += part if part.endswith("\n") else part + "\n"
        own = sources[name]
        return data + own

    result = run_make("A")
    assert result.returncode == 0, (
        f"make.sh A on dynamic inputs failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    for name in deps:
        path = os.path.join(BASE_DIR, "out", name + ".out")
        assert os.path.isfile(path), f"Missing transitive build output {path}"
        with open(path, "r") as f:
            assert f.read() == expected(name, patched), f"Incorrect dynamically derived output for {name}"
    with open(os.path.join(BASE_DIR, "final_output.log"), "r") as f:
        assert f.read() == expected("A", patched)

    before = {}
    for directory in ("src", "out"):
        for name in sorted(os.listdir(os.path.join(BASE_DIR, directory))):
            path = os.path.join(BASE_DIR, directory, name)
            with open(path, "rb") as f:
                before[(directory, name)] = f.read()

    result = run_make("A")
    assert result.returncode == 0, (
        f"Second make.sh A invocation failed; patches must be applied only once.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    for key, old_data in before.items():
        with open(os.path.join(BASE_DIR, key[0], key[1]), "rb") as f:
            assert f.read() == old_data, f"Repeated build unexpectedly changed {key[0]}/{key[1]}"

    patched["E"] = f"{token}-E-rebuilt-{secrets.token_hex(6)}\n"
    write(os.path.join(BASE_DIR, "src", "E.txt"), patched["E"])
    result = run_make("A")
    assert result.returncode == 0, (
        f"Rebuild after source change failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    for name in deps:
        with open(os.path.join(BASE_DIR, "out", name + ".out"), "r") as f:
            assert f.read() == expected(name, patched), f"{name} was not correctly rebuilt"
    with open(os.path.join(BASE_DIR, "final_output.log"), "r") as f:
        assert f.read() == expected("A", patched)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
