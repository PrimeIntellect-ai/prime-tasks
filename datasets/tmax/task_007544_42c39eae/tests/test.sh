#!/bin/bash
set -u
mkdir -p /logs/verifier

verify_submission() {
    if [ ! -f /home/user/extractor.go ] || [ -L /home/user/extractor.go ]; then
        echo "extractor.go is missing or is not a regular file" >&2
        return 1
    fi

    go build -o /tmp/extractor_submission /home/user/extractor.go || return 1
    [ -x /tmp/extractor_submission ] || return 1

    # Recreate the original fixtures so the submitted program, rather than a
    # pre-populated final state, must produce the expected results.
    python3 - <<'PY' || return 1
import os
import shutil
import zipfile

for path in ('/home/user/datasets', '/home/user/clean_data'):
    if os.path.lexists(path):
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)
        else:
            shutil.rmtree(path)
    os.makedirs(path)

for path in ('/home/user/malicious.log', '/home/home/user/.bashrc', '/home/user/etc/hosts'):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

os.makedirs('/home/user/datasets/text_data_dir')
with zipfile.ZipFile('/home/user/datasets/vision_data.zip', 'w') as z:
    z.writestr('images/img1.png', 'fake image data')
    z.writestr('labels.csv', 'img1,cat')
with zipfile.ZipFile('/home/user/datasets/text_data_dir/nlp_corpus.zip', 'w') as z:
    z.writestr('train.txt', 'hello world')
    z.writestr('test.txt', 'test data')
with zipfile.ZipFile('/home/user/datasets/audio_set.zip', 'w') as z:
    z.writestr('audio1.wav', 'fake audio')
    z.writestr('../../../home/user/.bashrc', 'echo "hacked"')
with zipfile.ZipFile('/home/user/datasets/text_data_dir/sensor_logs.zip', 'w') as z:
    z.writestr('log1.txt', 'sensor data')
    z.writestr('/etc/shadow', 'root:x:...')
    z.writestr('dir/../../../etc/hosts', '127.0.0.1 malicious.com')
PY

    cp -a /etc/shadow /tmp/verifier_shadow_backup || return 1
    timeout 30s /tmp/extractor_submission || return 1

    # Restore a sensitive file before failing if an unsafe implementation wrote it.
    if ! cmp -s /tmp/verifier_shadow_backup /etc/shadow; then
        cp -a /tmp/verifier_shadow_backup /etc/shadow
        echo "The extractor modified /etc/shadow" >&2
        return 1
    fi

    python3 - <<'PY' || return 1
import os

assert os.path.isfile('/home/user/extractor.go'), '/home/user/extractor.go is missing'

expected_files = [
    '/home/user/clean_data/vision_data/images/img1.png',
    '/home/user/clean_data/vision_data/labels.csv',
    '/home/user/clean_data/nlp_corpus/train.txt',
    '/home/user/clean_data/nlp_corpus/test.txt',
    '/home/user/clean_data/audio_set/audio1.wav',
    '/home/user/clean_data/sensor_logs/log1.txt'
]
for file_path in expected_files:
    assert os.path.isfile(file_path), f'Expected extracted file is missing: {file_path}'

expected_contents = {
    '/home/user/clean_data/vision_data/images/img1.png': b'fake image data',
    '/home/user/clean_data/vision_data/labels.csv': b'img1,cat',
    '/home/user/clean_data/nlp_corpus/train.txt': b'hello world',
    '/home/user/clean_data/nlp_corpus/test.txt': b'test data',
    '/home/user/clean_data/audio_set/audio1.wav': b'fake audio',
    '/home/user/clean_data/sensor_logs/log1.txt': b'sensor data',
}
for path, expected in expected_contents.items():
    with open(path, 'rb') as f:
        assert f.read() == expected, f'Extracted file has incorrect contents: {path}'

assert not os.path.exists('/home/user/clean_data/audio_set/../../../home/user/.bashrc'), 'Malicious file was extracted!'
assert not os.path.exists('/home/user/clean_data/sensor_logs/etc/shadow'), 'Malicious file was extracted!'
assert not os.path.exists('/home/user/clean_data/sensor_logs/dir/../../../etc/hosts'), 'Malicious file was extracted!'

log_path = '/home/user/malicious.log'
assert os.path.isfile(log_path), f'{log_path} is missing'
with open(log_path, 'r') as f:
    lines = [line.strip() for line in f if line.strip()]
expected_lines = [
    '[audio_set.zip] ../../../home/user/.bashrc',
    '[sensor_logs.zip] /etc/shadow',
    '[sensor_logs.zip] dir/../../../etc/hosts'
]
expected_lines.sort()
assert lines == expected_lines, f'Contents of {log_path} do not match the expected sorted output'
PY

    # Generate unpredictable additional archives after compilation and exercise
    # recursive discovery, content extraction, prefix-collision traversal, nested
    # traversal, and absolute-path rejection.
    python3 - <<'PY' || return 1
import base64
import json
import os
import secrets
import shutil
import zipfile

for path in ('/home/user/datasets', '/home/user/clean_data'):
    if os.path.lexists(path):
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)
        else:
            shutil.rmtree(path)
    os.makedirs(path)
try:
    os.remove('/home/user/malicious.log')
except FileNotFoundError:
    pass

token = secrets.token_hex(10)
main_base = 'case_' + token
second_base = 'recursive_' + token
main_zip = main_base + '.zip'
second_zip = second_base + '.zip'

safe = {
    f'/home/user/clean_data/{main_base}/ok/root.txt': secrets.token_bytes(37),
    f'/home/user/clean_data/{main_base}/ok/deep/data.bin': secrets.token_bytes(113),
    f'/home/user/clean_data/{main_base}/notes..txt': secrets.token_bytes(29),
    f'/home/user/clean_data/{second_base}/plain.txt': secrets.token_bytes(53),
}

prefix_entry = f'../{main_base}_evil/pwned.bin'
nested_entry = f'nested/../../escape_{token}/pwned.bin'
absolute_path = f'/tmp/{token}_absolute_pwned.bin'
malicious = {
    prefix_entry: secrets.token_bytes(41),
    nested_entry: secrets.token_bytes(43),
    absolute_path: secrets.token_bytes(47),
}

os.makedirs('/home/user/datasets/deep/subdirectory', exist_ok=True)
with zipfile.ZipFile('/home/user/datasets/' + main_zip, 'w') as z:
    z.writestr('ok/', b'')
    z.writestr('ok/root.txt', safe[f'/home/user/clean_data/{main_base}/ok/root.txt'])
    z.writestr('ok/deep/data.bin', safe[f'/home/user/clean_data/{main_base}/ok/deep/data.bin'])
    z.writestr('notes..txt', safe[f'/home/user/clean_data/{main_base}/notes..txt'])
    for name, payload in malicious.items():
        z.writestr(name, payload)
with zipfile.ZipFile('/home/user/datasets/deep/subdirectory/' + second_zip, 'w') as z:
    z.writestr('plain.txt', safe[f'/home/user/clean_data/{second_base}/plain.txt'])

canaries = {
    f'/home/user/clean_data/{main_base}_evil/pwned.bin': secrets.token_bytes(31),
    f'/home/user/clean_data/escape_{token}/pwned.bin': secrets.token_bytes(33),
    absolute_path: secrets.token_bytes(35),
}
for path, data in canaries.items():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)

manifest = {
    'safe': {p: base64.b64encode(v).decode() for p, v in safe.items()},
    'canaries': {p: base64.b64encode(v).decode() for p, v in canaries.items()},
    'malicious_payloads': [base64.b64encode(v).decode() for v in malicious.values()],
    'expected_log': sorted(f'[{main_zip}] {name}' for name in malicious),
}
with open('/tmp/dynamic_manifest.json', 'w') as f:
    json.dump(manifest, f)
PY

    timeout 30s /tmp/extractor_submission || return 1

    python3 - <<'PY' || return 1
import base64
import json
import os

with open('/tmp/dynamic_manifest.json') as f:
    manifest = json.load(f)

for path, encoded in manifest['safe'].items():
    assert os.path.isfile(path), f'Dynamically generated safe file was not extracted: {path}'
    with open(path, 'rb') as f:
        assert f.read() == base64.b64decode(encoded), f'Incorrect extracted contents: {path}'

for path, encoded in manifest['canaries'].items():
    assert os.path.isfile(path), f'Traversal canary disappeared: {path}'
    with open(path, 'rb') as f:
        assert f.read() == base64.b64decode(encoded), f'Malicious entry escaped its archive target: {path}'

malicious_payloads = {base64.b64decode(v) for v in manifest['malicious_payloads']}
for root, dirs, files in os.walk('/home/user/clean_data'):
    for name in files:
        path = os.path.join(root, name)
        with open(path, 'rb') as f:
            assert f.read() not in malicious_payloads, f'Malicious entry was extracted at {path}'

log_path = '/home/user/malicious.log'
assert os.path.isfile(log_path), f'{log_path} is missing after dynamic run'
with open(log_path, 'r', newline='') as f:
    raw = f.read()
expected = manifest['expected_log']
assert raw == ''.join(line + '\n' for line in expected), 'Dynamic malicious log is incomplete, unsorted, or incorrectly formatted'
PY
}

if verify_submission; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
