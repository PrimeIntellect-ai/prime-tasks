#!/bin/bash
set -u
mkdir -p /logs/verifier
ok=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib

def test_script_exists():
    script_path = '/home/user/process_assets.py'
    assert os.path.exists(script_path), f"Expected script at {script_path} is missing."
    assert os.path.isfile(script_path), f"{script_path} should be a file."

def test_extracted_directories_exist():
    base_dir = '/home/user/extracted'
    assert os.path.isdir(base_dir), f"Expected directory {base_dir} is missing."
    assert os.path.isdir(os.path.join(base_dir, 'module1')), "module1 directory missing."
    assert os.path.isdir(os.path.join(base_dir, 'module2')), "module2 directory missing."

def test_zip_files_deleted():
    base_dir = '/home/user/extracted'
    assert not os.path.exists(os.path.join(base_dir, 'module1.zip')), "module1.zip was not deleted."
    assert not os.path.exists(os.path.join(base_dir, 'module2.zip')), "module2.zip was not deleted."

def test_log_files_modified():
    app_log_path = '/home/user/extracted/module1/app.log'
    db_log_path = '/home/user/extracted/module2/db.log'
    assert os.path.isfile(app_log_path), f"{app_log_path} is missing."
    with open(app_log_path, 'r') as f:
        app_log_content = f.read()
    assert "DEBUG" not in app_log_content, "DEBUG lines were not removed from app.log."
    assert "WARN:" not in app_log_content, "WARN was not replaced in app.log."
    assert "WARNING: high memory usage detected" in app_log_content, "WARNING replacement incorrect in app.log."
    assert os.path.isfile(db_log_path), f"{db_log_path} is missing."
    with open(db_log_path, 'r') as f:
        db_log_content = f.read()
    assert "DEBUG" not in db_log_content, "DEBUG lines were not removed from db.log."
    assert "WARN:" not in db_log_content, "WARN was not replaced in db.log."
    assert "WARNING: reconnecting to database" in db_log_content, "WARNING replacement incorrect in db.log."

def test_manifest_exists_and_tmp_does_not():
    manifest_path = '/home/user/final_manifest.json'
    tmp_path = '/home/user/final_manifest.json.tmp'
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."
    assert not os.path.exists(tmp_path), f"Temporary manifest file {tmp_path} should have been renamed/deleted."

def test_manifest_content():
    manifest_path = '/home/user/final_manifest.json'
    base_dir = '/home/user/extracted'
    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            assert False, "Manifest is not a valid JSON file."
    expected_files = {
        'module1/app.log',
        'module1/main.py',
        'module2/db.log',
        'module2/config.yml'
    }
    assert set(manifest.keys()) == expected_files, f"Manifest keys do not match expected files. Found: {list(manifest.keys())}"
    for rel_path, expected_hash in manifest.items():
        abs_path = os.path.join(base_dir, rel_path)
        assert os.path.isfile(abs_path), f"File {abs_path} listed in manifest does not exist."
        with open(abs_path, 'rb') as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()
        assert actual_hash == expected_hash, f"Hash mismatch for {rel_path}. Expected {expected_hash}, got {actual_hash}."
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    ok=0
fi

if [ "$ok" -eq 1 ]; then
    if ! python3 << 'PY'
import base64
import hashlib
import io
import json
import secrets
import tarfile
import zipfile

nonce = secrets.token_hex(16)
sources = {
    'module1/app.log': (
        f'DEBUG: boot {nonce}\n'
        f'INFO: preserved {nonce}\n'
        f'prefix WARN middle {nonce}\n'
        f'keep-debug-lowercase debug {nonce}\n'
        f'trailing DEBUG marker {nonce}\n'
    ).encode(),
    'module1/main.py': f"print('dynamic-{nonce}')\n".encode(),
    'module2/db.log': (
        f'WARN: reconnect {nonce}\n'
        f'INFO: connected {nonce}\n'
        f'DEBUG details {nonce}\n'
        f'WARN WARN {nonce}\n'
    ).encode(),
    'module2/config.yml': f'timeout: {len(nonce)}\ntoken: {nonce}\n'.encode(),
}

def transformed(path, data):
    if not path.endswith('.log'):
        return data
    return b''.join(line.replace(b'WARN', b'WARNING')
                    for line in data.splitlines(keepends=True)
                    if b'DEBUG' not in line)

expected = {path: transformed(path, data) for path, data in sources.items()}
zip_blobs = {}
for module in ('module1', 'module2'):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
        for path, data in sources.items():
            if path.startswith(module + '/'):
                zf.writestr(path, data)
    zip_blobs[module + '.zip'] = buf.getvalue()

with tarfile.open('/home/user/project_data.tar.gz', 'w:gz') as tf:
    for name, data in zip_blobs.items():
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = 0o644
        tf.addfile(info, io.BytesIO(data))

with open('/tmp/dynamic_expected.json', 'w') as f:
    json.dump({
        'files': {p: base64.b64encode(d).decode() for p, d in expected.items()},
        'manifest': {p: hashlib.sha256(d).hexdigest() for p, d in expected.items()},
    }, f)
PY
    then
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    rm -rf /home/user/extracted
    rm -f /home/user/final_manifest.json /home/user/final_manifest.json.tmp
    cat << 'PY' > /tmp/run_with_audit.py
import base64
import json
import os
import runpy

record_path = '/tmp/atomic_record.json'
records = []

def absolute_path(value):
    value = os.fsdecode(os.fspath(value))
    return os.path.normpath(value if os.path.isabs(value) else os.path.abspath(value))

def audit(event, args):
    if event != 'os.rename' or len(args) < 2:
        return
    try:
        src = absolute_path(args[0])
        dst = absolute_path(args[1])
        item = {'src': src, 'dst': dst, 'tmp_data': None, 'json_valid': False}
        if src == '/home/user/final_manifest.json.tmp' and os.path.isfile(src):
            with open(src, 'rb') as f:
                data = f.read()
            item['tmp_data'] = base64.b64encode(data).decode()
            try:
                json.loads(data.decode('utf-8'))
                item['json_valid'] = True
            except Exception:
                pass
        records.append(item)
    except Exception as exc:
        records.append({'error': repr(exc)})

sys_audit = __import__('sys').addaudithook
sys_audit(audit)
try:
    runpy.run_path('/home/user/process_assets.py', run_name='__main__')
finally:
    with open(record_path, 'w') as f:
        json.dump(records, f)
PY
    if ! python3 /tmp/run_with_audit.py; then
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    cat << 'PY' > /tmp/test_dynamic_run.py
import base64
import hashlib
import json
import os

BASE = '/home/user/extracted'

def load_expected():
    with open('/tmp/dynamic_expected.json') as f:
        return json.load(f)

def test_script_created_exact_dynamic_outputs():
    expected = load_expected()
    actual_paths = set()
    for root, dirs, files in os.walk(BASE):
        for name in files:
            actual_paths.add(os.path.relpath(os.path.join(root, name), BASE).replace(os.sep, '/'))
    assert actual_paths == set(expected['files']), actual_paths
    for rel_path, encoded in expected['files'].items():
        with open(os.path.join(BASE, *rel_path.split('/')), 'rb') as f:
            assert f.read() == base64.b64decode(encoded), rel_path
    assert not os.path.exists(os.path.join(BASE, 'module1.zip'))
    assert not os.path.exists(os.path.join(BASE, 'module2.zip'))

def test_dynamic_manifest_is_complete_and_correct():
    expected = load_expected()['manifest']
    with open('/home/user/final_manifest.json', 'rb') as f:
        raw = f.read()
    manifest = json.loads(raw.decode('utf-8'))
    assert manifest == expected
    assert set(manifest) == {
        os.path.relpath(os.path.join(root, name), BASE).replace(os.sep, '/')
        for root, dirs, files in os.walk(BASE) for name in files
    }
    for path, digest in manifest.items():
        assert digest == digest.lower()
        assert len(digest) == 64
        with open(os.path.join(BASE, *path.split('/')), 'rb') as f:
            assert hashlib.sha256(f.read()).hexdigest() == digest

def test_manifest_was_atomically_renamed_from_complete_tmp_file():
    assert not os.path.exists('/home/user/final_manifest.json.tmp')
    with open('/tmp/atomic_record.json') as f:
        records = json.load(f)
    matching = [r for r in records
                if r.get('src') == '/home/user/final_manifest.json.tmp'
                and r.get('dst') == '/home/user/final_manifest.json'
                and r.get('json_valid')]
    assert matching, records
    with open('/home/user/final_manifest.json', 'rb') as f:
        final_data = f.read()
    assert any(base64.b64decode(r['tmp_data']) == final_data for r in matching)
PY
    if ! python3 -m pytest /tmp/test_dynamic_run.py -x --tb=short 2>&1; then
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
