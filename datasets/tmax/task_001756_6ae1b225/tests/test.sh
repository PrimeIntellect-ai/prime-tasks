#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import subprocess
import tempfile
import uuid
import zipfile
import pytest

EXECUTABLE = "/home/user/doc_filter"
DEFAULT_CONFIG = "/home/user/doc_rules.conf"


def run_doc_filter(target_dir, config_file=DEFAULT_CONFIG):
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"Executable at {EXECUTABLE} is not executable"

    try:
        result = subprocess.run(
            [EXECUTABLE, config_file, target_dir],
            capture_output=True,
            text=True,
            check=True,
            timeout=15
        )
        return result.stdout.strip().splitlines()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of doc_filter failed with return code {e.returncode}. Output: {e.stdout}\nError: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Execution of doc_filter timed out.")


def run_doc_filter_exact(target_dir, config_file):
    try:
        result = subprocess.run(
            [EXECUTABLE, config_file, target_dir],
            capture_output=True,
            text=True,
            check=True,
            timeout=15
        )
        return result.stdout.splitlines()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of doc_filter failed with return code {e.returncode}. Output: {e.stdout}\nError: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Execution of doc_filter timed out.")


def parse_output(output_lines):
    results = {}
    for line in output_lines:
        line = line.strip()
        if not line:
            continue
        if ": " not in line:
            pytest.fail(f"Invalid output format (missing ': '): '{line}'")
        filename, status = line.split(": ", 1)
        results[filename] = status
    return results


def test_clean_corpus():
    clean_dir = "/app/corpora/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    expected_files = sorted([f for f in os.listdir(clean_dir) if f.endswith('.zip')])
    output_lines = run_doc_filter(clean_dir)
    results = parse_output(output_lines)

    modified_files = []
    missing_files = []

    for filename in expected_files:
        if filename not in results:
            missing_files.append(filename)
        elif results[filename] != "CLEAN":
            modified_files.append(filename)

    error_msgs = []
    if missing_files:
        error_msgs.append(f"{len(missing_files)} of {len(expected_files)} clean missing from output: {missing_files}")
    if modified_files:
        error_msgs.append(f"{len(modified_files)} of {len(expected_files)} clean modified (not CLEAN): {modified_files}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_evil_corpus():
    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    expected_files = sorted([f for f in os.listdir(evil_dir) if f.endswith('.zip')])
    output_lines = run_doc_filter(evil_dir)
    results = parse_output(output_lines)

    bypassed_files = []
    missing_files = []

    for filename in expected_files:
        if filename not in results:
            missing_files.append(filename)
        elif results[filename] != "REJECT":
            bypassed_files.append(filename)

    error_msgs = []
    if missing_files:
        error_msgs.append(f"{len(missing_files)} of {len(expected_files)} evil missing from output: {missing_files}")
    if bypassed_files:
        error_msgs.append(f"{len(bypassed_files)} of {len(expected_files)} evil bypassed (not REJECT): {bypassed_files}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_binary_and_vendored_library_installation():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"Executable at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "doc_filter must be a compiled ELF executable"

    cmake_file = "/app/vendored/miniz-cpp-0.1.0/CMakeLists.txt"
    assert os.path.isfile(cmake_file), "Vendored CMakeLists.txt is missing"
    cmake_text = open(cmake_file, encoding="utf-8", errors="replace").read()
    assert re.search(r"\bminiz\.cpp\b", cmake_text), "CMakeLists.txt was not fixed to compile miniz.cpp"
    assert not re.search(r"\bminz\.cpp\b", cmake_text), "Broken minz.cpp source reference remains"

    patterns = [
        "/usr/local/lib*/libminiz_cpp.so*",
        "/usr/lib*/libminiz_cpp.so*",
        "/usr/lib/*/libminiz_cpp.so*",
        "/opt/**/libminiz_cpp.so*",
        "/home/user/**/libminiz_cpp.so*",
    ]
    installed = []
    for pattern in patterns:
        installed.extend(glob.glob(pattern, recursive="**" in pattern))
    installed = [p for p in installed if os.path.isfile(p) and "/app/vendored/" not in p]
    assert installed, "No locally installed libminiz_cpp shared library was found"

    dynamic = subprocess.run(
        ["readelf", "-d", EXECUTABLE], capture_output=True, text=True, check=True
    ).stdout
    assert "libminiz_cpp" in dynamic, "doc_filter is not dynamically linked against the installed miniz_cpp library"


def write_zip(path, members, compression=zipfile.ZIP_DEFLATED):
    with zipfile.ZipFile(path, "w", compression=compression) as zf:
        for name, data in members:
            zf.writestr(name, data)


def test_generated_archives_dynamic_config_exact_sorted_output():
    token = uuid.uuid4().hex[:12]
    with tempfile.TemporaryDirectory(prefix="doc_filter_verify_") as root:
        archive_dir = os.path.join(root, "incoming_" + token)
        os.mkdir(archive_dir)
        config_true = os.path.join(root, "rules_true_" + token + ".conf")
        config_false = os.path.join(root, "rules_false_" + token + ".conf")

        with open(config_true, "w") as f:
            f.write("ALLOWED_EXT=.qmd,.asset\nMAX_UNCOMPRESSED_TOTAL_MB=1\nREJECT_HIDDEN=true\n")
        with open(config_false, "w") as f:
            f.write("ALLOWED_EXT=.qmd,.asset\nMAX_UNCOMPRESSED_TOTAL_MB=1\nREJECT_HIDDEN=false\n")

        names = {
            "clean1": f"{token}_zeta_docs.zip",
            "clean2": f"{token}_alpha_assets.zip",
            "badext": f"{token}_middle_type.zip",
            "hiddenfile": f"{token}_hidden_file.zip",
            "hiddendir": f"{token}_hidden_dir.zip",
            "large": f"{token}_oversize.zip",
            "corrupt": f"{token}_broken.zip",
        }

        write_zip(os.path.join(archive_dir, names["clean1"]), [
            ("guide.qmd", b"guide"),
            ("chapters/intro.qmd", b"intro"),
        ])
        write_zip(os.path.join(archive_dir, names["clean2"]), [
            ("images/logo.asset", b"asset-data"),
        ])
        write_zip(os.path.join(archive_dir, names["badext"]), [
            ("guide.qmd", b"ok"),
            ("payload.bin", b"not allowed"),
        ])
        write_zip(os.path.join(archive_dir, names["hiddenfile"]), [
            (".notes.qmd", b"hidden"),
        ])
        write_zip(os.path.join(archive_dir, names["hiddendir"]), [
            (".private/readme.qmd", b"hidden directory"),
        ])
        write_zip(os.path.join(archive_dir, names["large"]), [
            ("large.qmd", b"X" * (1024 * 1024 + 1)),
        ])
        with open(os.path.join(archive_dir, names["corrupt"]), "wb") as f:
            f.write(b"PK\x03\x04" + os.urandom(73))

        with open(os.path.join(archive_dir, "not_an_archive.txt"), "w") as f:
            f.write("must not appear in output")

        expected_true_status = {
            names["clean1"]: "CLEAN",
            names["clean2"]: "CLEAN",
            names["badext"]: "REJECT",
            names["hiddenfile"]: "REJECT",
            names["hiddendir"]: "REJECT",
            names["large"]: "REJECT",
            names["corrupt"]: "REJECT",
        }
        expected_true = [f"{name}: {expected_true_status[name]}" for name in sorted(expected_true_status)]
        actual_true = run_doc_filter_exact(archive_dir, config_true)
        assert actual_true == expected_true, (
            "Output must contain exactly one correctly formatted line per ZIP, with no extras, "
            f"sorted by filename. Expected {expected_true!r}, got {actual_true!r}"
        )

        expected_false_status = dict(expected_true_status)
        expected_false_status[names["hiddenfile"]] = "CLEAN"
        expected_false_status[names["hiddendir"]] = "CLEAN"
        expected_false = [f"{name}: {expected_false_status[name]}" for name in sorted(expected_false_status)]
        actual_false = run_doc_filter_exact(archive_dir, config_false)
        assert actual_false == expected_false, (
            "REJECT_HIDDEN must be parsed dynamically and output must remain exact and sorted. "
            f"Expected {expected_false!r}, got {actual_false!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
