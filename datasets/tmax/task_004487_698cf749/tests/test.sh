#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import os
import secrets
import subprocess
import sys
import urllib.error
import urllib.request

import pytest

CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
API_URL = "http://127.0.0.1:8000/validate-patch"
API_PATH = "/home/user/api.py"
VENDORED_DIR = "/app/vendored/patch-processor"


def request_status(data):
    req = urllib.request.Request(
        API_URL,
        data=data,
        headers={"Content-Type": "text/plain"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except urllib.error.URLError as exc:
        pytest.fail(f"Could not connect to API: {exc.reason}")


def make_diff(path, removed="old", added="new"):
    return (
        f"--- a/{path}\n"
        f"+++ b/{path}\n"
        "@@ -1 +1 @@\n"
        f"-{removed}\n"
        f"+{added}\n"
    ).encode()


def test_api_artifact_exists_and_uses_patch_processor_parse():
    assert os.path.isfile(API_PATH), f"Missing API artifact: {API_PATH}"
    with open(API_PATH, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=API_PATH)

    module_aliases = set()
    parse_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "patch_processor":
                    module_aliases.add(alias.asname or "patch_processor")
        elif isinstance(node, ast.ImportFrom) and node.module == "patch_processor":
            for alias in node.names:
                if alias.name == "parse":
                    parse_aliases.add(alias.asname or "parse")

    # Track ordinary aliases such as parser = patch_processor.parse.
    changed = True
    while changed:
        changed = False
        for node in ast.walk(tree):
            if not isinstance(node, (ast.Assign, ast.AnnAssign)):
                continue
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            names = [target.id for target in targets if isinstance(target, ast.Name)]
            is_parse = (
                isinstance(value, ast.Name) and value.id in parse_aliases
            ) or (
                isinstance(value, ast.Attribute)
                and value.attr == "parse"
                and isinstance(value.value, ast.Name)
                and value.value.id in module_aliases
            )
            if is_parse:
                for name in names:
                    if name not in parse_aliases:
                        parse_aliases.add(name)
                        changed = True

    calls_parse = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id in parse_aliases:
            calls_parse = True
        elif (
            isinstance(func, ast.Attribute)
            and func.attr == "parse"
            and isinstance(func.value, ast.Name)
            and func.value.id in module_aliases
        ):
            calls_parse = True

    assert calls_parse, "api.py must call patch_processor.parse(diff_text)"


def test_vendored_package_imports_and_parse_works():
    code = r'''
import patch_processor
sample = "--- a/src/check.py\n+++ b/src/check.py\n@@ -1 +1 @@\n-old\n+new\n"
assert patch_processor.parse(sample) == ["src/check.py"]
'''
    env = os.environ.copy()
    env["PYTHONPATH"] = VENDORED_DIR + os.pathsep + env.get("PYTHONPATH", "")
    result = subprocess.run(
        [sys.executable, "-c", code],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_api_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.diff"))
    assert clean_files, "Clean corpus files missing"

    failed_files = []
    for filepath in clean_files:
        with open(filepath, "rb") as handle:
            data = handle.read()
        status = request_status(data)
        if status != 200:
            failed_files.append((os.path.basename(filepath), status))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean files rejected: {failed_files}"
        )


def test_api_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.diff"))
    assert evil_files, "Evil corpus files missing"

    failed_files = []
    for filepath in evil_files:
        with open(filepath, "rb") as handle:
            data = handle.read()
        status = request_status(data)
        if status != 403:
            failed_files.append((os.path.basename(filepath), status))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil files bypassed: {failed_files}"
        )


def test_generated_safe_patches_are_accepted():
    token = secrets.token_hex(8)
    safe_paths = [
        f"src/{token}.py",
        f"ios/Secretariat/{token}.txt",
        f"android/keystore/{token}.txt",
        f".github/workflow/{token}.yml",
        f"docs/{token}-Secrets-guide.md",
    ]

    # Forbidden-looking text in hunk contents is not a modified filepath.
    forbidden_content = (
        "mentions ios/Secrets/file.pem, android/keystores/release.jks, "
        ".github/workflows/build.yml, ../outside, and ..\\outside"
    )
    cases = [make_diff(path, "plain", forbidden_content) for path in safe_paths]
    for index in range(8):
        cases.append(make_diff(f"src/generated_{token}_{index}.txt"))

    failures = []
    for index, data in enumerate(cases):
        status = request_status(data)
        if status != 200:
            failures.append((index, status))
    assert not failures, f"Generated safe patches rejected: {failures}"


def test_generated_forbidden_paths_are_rejected():
    token = secrets.token_hex(8)
    evil_paths = [
        f"ios/Secrets/{token}.pem",
        f"packages/ios/Secrets/{token}.mobileprovision",
        f"android/keystores/{token}.jks",
        f"mobile/android/keystores/{token}.properties",
        f".github/workflows/{token}.yml",
        f"repo/.github/workflows/{token}.yaml",
        f"../outside/{token}.txt",
        f"src/../../outside/{token}.txt",
        f"..\\outside\\{token}.txt",
        f"src\\..\\outside\\{token}.txt",
    ]

    # Mix a forbidden destination with a normal destination to ensure all parsed
    # paths are validated rather than only the first one.
    mixed = (
        f"--- a/src/normal_{token}.txt\n"
        f"+++ b/src/normal_{token}.txt\n"
        "@@ -1 +1 @@\n-old\n+new\n"
        f"--- a/tools/{token}.txt\n"
        f"+++ b/tools/.github/workflows/{token}.yml\n"
        "@@ -1 +1 @@\n-old\n+new\n"
    ).encode()

    cases = [make_diff(path) for path in evil_paths] + [mixed]
    failures = []
    for index, data in enumerate(cases):
        status = request_status(data)
        if status != 403:
            failures.append((evil_paths[index] if index < len(evil_paths) else "mixed", status))
    assert not failures, f"Generated malicious patches bypassed validation: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
