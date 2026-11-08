#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import email.parser
import json
import os
import re
import secrets
import string
import subprocess
import tempfile
import zipfile

import pytest


def run_dsl(program):
    interpreter_path = "/home/user/interpreter.sh"
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
        f.write(program)
        temp_path = f.name
    try:
        return subprocess.run(
            [interpreter_path, temp_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
    finally:
        os.remove(temp_path)


def random_text(min_len=5, max_len=30):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(max_len - min_len + 1) + min_len))


def test_interpreter_sh_exists_and_executable():
    interpreter_path = "/home/user/interpreter.sh"
    assert os.path.isfile(interpreter_path), f"{interpreter_path} is missing"
    assert os.access(interpreter_path, os.X_OK), f"{interpreter_path} is not executable"
    with open(interpreter_path, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line in ("#!/bin/bash", "#!/usr/bin/bash", "#!/usr/bin/env bash"), \
        "interpreter.sh must be a Bash script with a Bash shebang"


def test_interpreter_sh_correctness():
    interpreter_path = "/home/user/interpreter.sh"
    # Preserve the original fixed regression case.
    test_dsl = """PUSH aGVsbG8
PUSH 3b3JsZA==
CONCAT
B64DEC
PRINT
"""
    result = run_dsl(test_dsl)
    assert result.returncode == 0, f"Interpreter failed with return code {result.returncode}. Stderr: {result.stderr}"
    assert result.stdout == "helloworld", f"Interpreter output incorrect. Expected 'helloworld', got {repr(result.stdout)}"

    # Exercise every instruction on unpredictable values, deriving expected output here.
    for _ in range(6):
        left = random_text()
        right = random_text()
        result = run_dsl(f"PUSH {left}\nPUSH {right}\nCONCAT\nPRINT\n")
        assert result.returncode == 0, result.stderr
        assert result.stdout == left + right

        plaintext = random_text(20, 60)
        encoded = base64.b64encode(plaintext.encode()).decode()
        cut1 = secrets.randbelow(len(encoded) - 2) + 1
        cut2 = secrets.randbelow(len(encoded) - cut1 - 1) + cut1 + 1
        chunks = (encoded[:cut1], encoded[cut1:cut2], encoded[cut2:])
        program = (
            f"PUSH {chunks[0]}\nPUSH {chunks[1]}\nCONCAT\n"
            f"PUSH {chunks[2]}\nCONCAT\nB64DEC\nPRINT\n"
        )
        result = run_dsl(program)
        assert result.returncode == 0, result.stderr
        assert result.stdout == plaintext

        prefix = random_text()
        suffix = random_text()
        phrase = random_text() + " " + random_text()
        encoded_phrase = base64.b64encode(phrase.encode()).decode()
        split = secrets.randbelow(len(encoded_phrase) - 1) + 1
        program = (
            f"PUSH {prefix}\nPUSH {encoded_phrase[:split]}\n"
            f"PUSH {encoded_phrase[split:]}\nCONCAT\nB64DEC\nCONCAT\n"
            f"PUSH {suffix}\nCONCAT\nPRINT\n"
        )
        result = run_dsl(program)
        assert result.returncode == 0, result.stderr
        assert result.stdout == prefix + phrase + suffix

        result = run_dsl(f"PUSH {left}\nPUSH {right}\nPRINT\nPRINT\n")
        assert result.returncode == 0, result.stderr
        assert result.stdout == right + left


def test_metadata_json():
    metadata_path = "/home/user/metadata.json"
    assert os.path.isfile(metadata_path), f"{metadata_path} is missing"
    with open(metadata_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{metadata_path} does not contain valid JSON")

    assert data.get("version") == "1.2.3", f"Expected version '1.2.3' in metadata.json, got {data.get('version')}"
    assert data.get("deps") == ["requests"], f"Expected deps ['requests'] in metadata.json, got {data.get('deps')}"

    recipe_result = subprocess.run(
        ["/home/user/interpreter.sh", "/home/user/legacy_pkg/recipe.dsl"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert recipe_result.returncode == 0, recipe_result.stderr
    try:
        recovered = json.loads(recipe_result.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Interpreter output for recipe.dsl is not valid JSON: {exc}")
    assert recovered == data, "metadata.json does not match the interpreter output for recipe.dsl"


def test_pyproject_toml_updated():
    toml_path = "/home/user/legacy_pkg/pyproject.toml"
    assert os.path.isfile(toml_path), f"{toml_path} is missing"

    with open(toml_path, "r") as f:
        content = f.read()

    assert "# INSERT_VERSION_HERE" not in content, "Placeholder # INSERT_VERSION_HERE was not removed from pyproject.toml"
    assert "# INSERT_DEPS_HERE" not in content, "Placeholder # INSERT_DEPS_HERE was not removed from pyproject.toml"
    assert 'version = "1.2.3"' in content or "version='1.2.3'" in content.replace(" ", ""), "pyproject.toml missing correct version assignment"
    assert 'dependencies = ["requests"]' in content or "dependencies=['requests']" in content.replace(" ", ""), "pyproject.toml missing correct dependencies assignment"

    try:
        import tomllib
    except ImportError:
        from pip._vendor import tomli as tomllib
    with open(toml_path, "rb") as f:
        parsed = tomllib.load(f)
    project = parsed.get("project", {})
    assert project.get("name") == "legacy_pkg"
    assert project.get("version") == "1.2.3"
    assert project.get("dependencies") == ["requests"]


def test_wheel_exists_in_artifacts():
    wheel_path = "/home/user/artifacts/legacy_pkg-1.2.3-py3-none-any.whl"
    assert os.path.isfile(wheel_path), f"Wheel file {wheel_path} is missing. Did you build the package and move it to artifacts?"
    assert zipfile.is_zipfile(wheel_path), "Artifact is not a valid wheel/ZIP archive"

    with zipfile.ZipFile(wheel_path) as wheel:
        assert wheel.testzip() is None, "Wheel contains corrupt members"
        names = wheel.namelist()
        assert "legacy_pkg/__init__.py" in names, "Wheel does not contain the legacy_pkg package"
        metadata_files = [n for n in names if n.endswith(".dist-info/METADATA")]
        wheel_files = [n for n in names if n.endswith(".dist-info/WHEEL")]
        record_files = [n for n in names if n.endswith(".dist-info/RECORD")]
        assert len(metadata_files) == 1, "Wheel must contain exactly one dist-info/METADATA file"
        assert len(wheel_files) == 1, "Wheel is missing dist-info/WHEEL"
        assert len(record_files) == 1, "Wheel is missing dist-info/RECORD"

        metadata_text = wheel.read(metadata_files[0]).decode("utf-8")
        metadata = email.parser.Parser().parsestr(metadata_text)
        normalize = lambda value: re.sub(r"[-_.]+", "-", value).lower()
        assert normalize(metadata.get("Name", "")) == "legacy-pkg"
        assert metadata.get("Version") == "1.2.3"
        requirements = metadata.get_all("Requires-Dist", [])
        assert any(normalize(req.split(";", 1)[0].strip().split()[0]) == "requests" for req in requirements), \
            "Built wheel metadata does not declare the requests dependency"

    with tempfile.TemporaryDirectory() as target:
        install = subprocess.run(
            ["python3", "-m", "pip", "install", "--no-deps", "--target", target, wheel_path],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert install.returncode == 0, f"Wheel cannot be installed: {install.stderr}"
        env = os.environ.copy()
        env["PYTHONPATH"] = target
        check = subprocess.run(
            ["python3", "-c", "import json, legacy_pkg; print(json.dumps([legacy_pkg.hello(), legacy_pkg.__file__]))"],
            cwd="/tmp",
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert check.returncode == 0, f"Installed wheel cannot be imported: {check.stderr}"
        hello, module_path = json.loads(check.stdout)
        assert hello == "Legacy package restored!"
        assert os.path.realpath(module_path).startswith(os.path.realpath(target) + os.sep)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
