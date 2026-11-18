#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid
import zlib

import pytest
import yaml

SCRIPT_PATH = "/home/user/config_filter.py"
VENDORED_DIR = "/app/vendored/lzconfig_v1.0.0"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
APPROVED_DIR = "/home/user/approved_configs"


def output_path(input_path):
    return os.path.join(APPROVED_DIR, Path(input_path).stem + ".yaml")


def read_lzc(path):
    with open(path, "rb") as f:
        return json.loads(zlib.decompress(f.read()).decode("utf-8"))


def read_yaml(path):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"


def test_vendored_package_is_fixed_and_installed():
    core_path = os.path.join(VENDORED_DIR, "lzconfig", "core.py")
    assert os.path.isfile(core_path), f"Vendored core missing at {core_path}"
    assert importlib.metadata.version("lzconfig") == "1.0.0"

    payload = {"probe": str(uuid.uuid4()), "role": "user"}
    code = (
        "import json,zlib,lzconfig; "
        f"expected={payload!r}; "
        "data=zlib.compress(json.dumps(expected).encode()); "
        "assert lzconfig.decompress(data)==expected"
    )
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    installed = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, env=env)
    assert installed.returncode == 0, installed.stderr

    vendored_code = (
        f"import sys; sys.path.insert(0, {VENDORED_DIR!r}); " + code
    )
    vendored = subprocess.run([sys.executable, "-c", vendored_code], capture_output=True, text=True, env=env)
    assert vendored.returncode == 0, vendored.stderr


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus missing at {CLEAN_CORPUS}"
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus missing at {EVIL_CORPUS}"
    os.makedirs(APPROVED_DIR, exist_ok=True)

    evil_files = sorted(f for f in os.listdir(EVIL_CORPUS) if f.endswith(".lzc"))
    clean_files = sorted(f for f in os.listdir(CLEAN_CORPUS) if f.endswith(".lzc"))
    evil_bypassed = []
    clean_failed = []

    for ef in evil_files:
        ef_path = os.path.join(EVIL_CORPUS, ef)
        yaml_path = output_path(ef_path)
        if os.path.exists(yaml_path):
            os.remove(yaml_path)
        result = subprocess.run([sys.executable, SCRIPT_PATH, ef_path], capture_output=True)
        if result.returncode != 1 or os.path.exists(yaml_path):
            evil_bypassed.append(ef)

    for cf in clean_files:
        cf_path = os.path.join(CLEAN_CORPUS, cf)
        yaml_path = output_path(cf_path)
        if os.path.exists(yaml_path):
            os.remove(yaml_path)
        result = subprocess.run([sys.executable, SCRIPT_PATH, cf_path], capture_output=True)
        if result.returncode != 0 or not os.path.isfile(yaml_path):
            clean_failed.append(cf)
            continue
        try:
            if read_yaml(yaml_path) != read_lzc(cf_path):
                clean_failed.append(cf)
        except Exception:
            clean_failed.append(cf)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean failed or produced incorrect YAML: {', '.join(clean_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_novel_generated_configurations_and_lzconfig_use(tmp_path):
    os.makedirs(APPROVED_DIR, exist_ok=True)

    marker = tmp_path / "lzconfig_calls"
    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    (hook_dir / "sitecustomize.py").write_text(
        "import os\n"
        "try:\n"
        "    import lzconfig\n"
        "    import lzconfig.core as _core\n"
        "    _original = _core.decompress\n"
        "    def _tracked(data):\n"
        "        with open(os.environ['LZCONFIG_CALL_MARKER'], 'a') as f:\n"
        "            f.write(os.environ['LZCONFIG_CALL_TOKEN'] + '\\n')\n"
        "        return _original(data)\n"
        "    _core.decompress = _tracked\n"
        "    lzconfig.decompress = _tracked\n"
        "except Exception:\n"
        "    pass\n",
        encoding="utf-8",
    )

    nonce = uuid.uuid4().hex
    clean_cases = [
        {
            "role": "user",
            f"setting_{nonce}": "enabled",
            "cache_dir": f"relative/{nonce}/cache",
            "items": [1, True, None, {"name": nonce}],
        },
        {
            "theme": f"novel-{nonce}",
            "backup_path": f"var/data/{nonce}.db",
            "ordinary_value": "/absolute/is/allowed/for/non-path-keys",
        },
    ]
    evil_cases = [
        {f"_internal_{nonce}": "secret", "role": "user"},
        {"role": f"admin-{nonce}"},
        {"role": 7},
        {f"plugin_path": f"/opt/{nonce}/plugins"},
        {f"log_dir": f"safe/{nonce}/../private"},
    ]

    def invoke(data, expected_clean):
        input_name = f"generated_{uuid.uuid4().hex}.lzc"
        input_path = tmp_path / input_name
        input_path.write_bytes(zlib.compress(json.dumps(data).encode("utf-8")))
        yaml_path = output_path(str(input_path))
        if os.path.lexists(yaml_path):
            os.remove(yaml_path)

        token = uuid.uuid4().hex
        env = os.environ.copy()
        env["LZCONFIG_CALL_MARKER"] = str(marker)
        env["LZCONFIG_CALL_TOKEN"] = token
        env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH, str(input_path)],
            capture_output=True,
            text=True,
            env=env,
        )

        calls = marker.read_text(encoding="utf-8").splitlines() if marker.exists() else []
        assert token in calls, "config_filter.py did not call lzconfig.decompress"

        if expected_clean:
            assert result.returncode == 0, result.stderr
            assert os.path.isfile(yaml_path), f"Missing YAML output {yaml_path}"
            assert read_yaml(yaml_path) == data, "Produced YAML does not match decompressed configuration"
        else:
            assert result.returncode == 1, result.stderr
            assert not os.path.exists(yaml_path), "Rejected configuration produced a YAML file"

    for data in clean_cases:
        invoke(data, True)
    for data in evil_cases:
        invoke(data, False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
