#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import subprocess
import uuid

import pytest


def test_build_validator_exists():
    script_path = "/home/user/build_validator.py"
    assert os.path.isfile(script_path), f"The required script {script_path} does not exist."


def test_corpus_validation():
    script_path = "/home/user/build_validator.py"
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    clean_subdirs = [os.path.join(clean_dir, d) for d in os.listdir(clean_dir) if os.path.isdir(os.path.join(clean_dir, d))]
    evil_subdirs = [os.path.join(evil_dir, d) for d in os.listdir(evil_dir) if os.path.isdir(os.path.join(evil_dir, d))]

    assert len(clean_subdirs) == 50, f"Expected 50 clean projects, found {len(clean_subdirs)}"
    assert len(evil_subdirs) == 50, f"Expected 50 evil projects, found {len(evil_subdirs)}"

    failed_clean = []
    for d in clean_subdirs:
        result = subprocess.run(["python3", script_path, d], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(d))

    failed_evil = []
    for d in evil_subdirs:
        result = subprocess.run(["python3", script_path, d], capture_output=True)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(d))

    error_messages = []
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_subdirs)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_subdirs)} evil bypassed: {', '.join(failed_evil)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def _write_project(path, requests_ok, express, flask, malicious, checksum_ok):
    os.makedirs(path)

    deps = {}
    if random.choice([True, False]):
        deps["left-pad"] = "^1.3.0"
    if express:
        deps["express"] = "^4.18.2"
    else:
        deps["lodash"] = "^4.17.21"
    if random.choice([True, False]):
        deps["chalk"] = "^5.0.0"

    deps_text = json.dumps(deps, separators=(",", ":"))
    checksum = hashlib.md5(deps_text.encode("utf-8")).hexdigest()
    if not checksum_ok:
        checksum = "0" * 32 if checksum != "0" * 32 else "f" * 32

    with open(os.path.join(path, "package.json"), "w", encoding="utf-8") as f:
        json.dump({"name": "generated-project", "dependencies": deps, "md5": checksum}, f)

    request_specs = ["requests>=3.9", "requests==3.9", "requests>=4.0"] if requests_ok else ["requests==3.8", "requests<3.9"]
    requirements = [random.choice(request_specs)]
    if flask:
        requirements.append("flask>=1.1.2")
    requirements.append("urllib3>=1.26")
    with open(os.path.join(path, "requirements.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(requirements) + "\n")

    build_text = "#!/bin/bash\necho 'Building generated project'\n"
    if malicious:
        build_text += "echo 'ZXZhbCBiYXNo' | base64 -d | bash\n"
    with open(os.path.join(path, ".build.sh"), "w", encoding="utf-8") as f:
        f.write(build_text)


def test_validator_on_unlabeled_generated_projects(tmp_path):
    script_path = "/home/user/build_validator.py"

    # Include valid projects and each individual rule violation, then randomized
    # combinations. Directory names intentionally reveal no expected result.
    cases = [
        (True, False, False, False, True),
        (True, True, True, False, True),
        (False, False, False, False, True),
        (True, True, False, False, True),
        (True, False, False, True, True),
        (True, False, False, False, False),
    ]
    rng = random.SystemRandom()
    for _ in range(26):
        cases.append(tuple(rng.choice([True, False]) for _ in range(5)))
    rng.shuffle(cases)

    failures = []
    for requests_ok, express, flask, malicious, checksum_ok in cases:
        project = tmp_path / ("project_" + uuid.uuid4().hex)
        _write_project(str(project), requests_ok, express, flask, malicious, checksum_ok)
        expected = 0 if (requests_ok and (not express or flask) and not malicious and checksum_ok) else 1
        result = subprocess.run(
            ["python3", script_path, str(project)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != expected:
            failures.append(
                f"{project.name}: expected {expected}, got {result.returncode}; "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )

    assert not failures, "Generated project validation failures:\n" + "\n".join(failures)


def test_extracted_rules_exist_and_cover_audio_rules():
    rules_path = "/home/user/extracted_rules.txt"
    assert os.path.isfile(rules_path), f"The required rules file {rules_path} does not exist."
    with open(rules_path, encoding="utf-8", errors="replace") as f:
        text = f.read().lower()
    assert text.strip(), "extracted_rules.txt is empty"
    for term in ("requests", "3.9", "express", "flask", "base64", "bash", "md5", "dependencies"):
        assert term in text, f"extracted_rules.txt does not document the audio rule involving {term!r}"


def test_verify_all_script():
    verify_path = "/home/user/verify_all.sh"
    assert os.path.isfile(verify_path), f"The required script {verify_path} does not exist."
    result = subprocess.run(["bash", verify_path], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"verify_all.sh exited {result.returncode}: {result.stderr}"
    assert result.stdout == "CLEAN PASSED\nEVIL REJECTED\n", f"Unexpected verify_all.sh output: {result.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
