#!/bin/bash
set -u
mkdir -p /logs/verifier

run_verifier() (
set -e

BACKUP_DATASET=$(mktemp)
cp /app/dataset.tar.gz "$BACKUP_DATASET"
restore_dataset() {
    cp "$BACKUP_DATASET" /app/dataset.tar.gz 2>/dev/null || true
}
trap restore_dataset EXIT

# The requested implementation must be a real, buildable Go source file.
test -f /home/user/server.go
test ! -L /home/user/server.go
grep -Eq '^[[:space:]]*package[[:space:]]+main([[:space:]]|$)' /home/user/server.go
go build -o /tmp/submitted_sensor_server /home/user/server.go

# Retain an implementation-level assertion for the explicitly required
# temp-file-and-rename atomic write pattern.
python3 - <<'PY'
import re
src = open('/home/user/server.go', encoding='utf-8').read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'//[^\n]*', '', src)
assert re.search(r'\b(?:os\.)?Rename\s*\(', src), 'server.go does not rename temporary chunk files atomically'
assert (re.search(r'\b(?:os\.)?CreateTemp\s*\(', src)
        or re.search(r'\b(?:ioutil\.)?TempFile\s*\(', src)
        or (re.search(r'\b(?:os\.)?(?:Create|OpenFile)\s*\(', src)
            and re.search(r'(?i)temp|tmp', src))), 'server.go does not create temporary chunk files'
PY

kill_port_8080() {
python3 - <<'PY'
import os, signal, time
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
            inodes.add(fields[9])
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    fdroot = f'/proc/{name}/fd'
    try:
        fds = os.listdir(fdroot)
    except OSError:
        continue
    for fd in fds:
        try:
            target = os.readlink(f'{fdroot}/{fd}')
        except OSError:
            continue
        if target.startswith('socket:[') and target[8:-1] in inodes:
            try:
                os.kill(int(name), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
            break
time.sleep(0.5)
PY
}

stop_pid() {
    pid="$1"
    kill "$pid" 2>/dev/null || true
    sleep 0.3
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

wait_for_api() {
python3 - <<'PY'
import time, urllib.request
last = None
for _ in range(80):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8080/api/data/__verifier_probe__/meta', timeout=.4) as r:
            pass
    except urllib.error.HTTPError:
        raise SystemExit(0)
    except Exception as e:
        last = e
        time.sleep(.1)
raise AssertionError(f'compiled Go server did not listen on 127.0.0.1:8080: {last}')
PY
}

# Exercise safe extraction with hostile tar and nested-zip member names. A safe
# implementation may reject the archive or ignore the hostile members, but it
# must never create either requested escape target.
rm -f /tmp/verifier_tar_escape /tmp/verifier_zip_escape
python3 - <<'PY'
import io, tarfile, zipfile
zbuf = io.BytesIO()
with zipfile.ZipFile(zbuf, 'w') as z:
    z.writestr('sensor_safety/meta.txt', 'safety\n')
    z.writestr('sensor_safety/data.bin', b'x')
    z.writestr('../../../../../../../../tmp/verifier_zip_escape', b'unsafe')
with tarfile.open('/app/dataset.tar.gz', 'w:gz') as t:
    payload = zbuf.getvalue()
    info = tarfile.TarInfo('sensor_safety.zip')
    info.size = len(payload)
    t.addfile(info, io.BytesIO(payload))
    bad = b'unsafe'
    info = tarfile.TarInfo('/tmp/verifier_tar_escape')
    info.size = len(bad)
    t.addfile(info, io.BytesIO(bad))
PY
kill_port_8080
/tmp/submitted_sensor_server >/tmp/safety-server.log 2>&1 &
SAFETY_PID=$!
sleep 2
stop_pid "$SAFETY_PID"
test ! -e /tmp/verifier_tar_escape
test ! -e /tmp/verifier_zip_escape

# Run the submitted Go artifact against unpredictable sensor contents. This
# prevents a fixed/static implementation for the two known byte ranges.
python3 - <<'PY'
import io, json, os, secrets, tarfile, zipfile
sensor = 'sensor_verify_' + secrets.token_hex(5)
meta = 'verification-' + secrets.token_hex(12) + '\n'
data = os.urandom(2_000_123)
zbuf = io.BytesIO()
with zipfile.ZipFile(zbuf, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    z.writestr(sensor + '/meta.txt', meta)
    z.writestr(sensor + '/data.bin', data)
with tarfile.open('/app/dataset.tar.gz', 'w:gz') as t:
    payload = zbuf.getvalue()
    info = tarfile.TarInfo(sensor + '.zip')
    info.size = len(payload)
    t.addfile(info, io.BytesIO(payload))
open('/tmp/challenge_data.bin', 'wb').write(data)
json.dump({'sensor': sensor, 'meta': meta}, open('/tmp/challenge.json', 'w'))
PY
rm -rf /home/user/processed
mkdir -p /home/user/processed
CHALLENGE_SENSOR=$(python3 -c "import json; print(json.load(open('/tmp/challenge.json'))['sensor'])")
redis-cli -h 127.0.0.1 -p 6379 DEL "sensor_chunks:$CHALLENGE_SENSOR" >/dev/null
kill_port_8080
/tmp/submitted_sensor_server >/tmp/challenge-server.log 2>&1 &
CHALLENGE_PID=$!
wait_for_api
python3 - <<'PY'
import json, os, socket, stat, urllib.request
cfg = json.load(open('/tmp/challenge.json'))
sensor, meta = cfg['sensor'], cfg['meta']
data = open('/tmp/challenge_data.bin', 'rb').read()

def get(url):
    with urllib.request.urlopen(url, timeout=3) as r:
        assert r.status == 200
        return r.read()

def redis_get(key):
    s = socket.create_connection(('127.0.0.1', 6379), 2)
    f = s.makefile('rb')
    b = key.encode()
    s.sendall(b'*2\r\n$3\r\nGET\r\n$%d\r\n%s\r\n' % (len(b), b))
    size = int(f.readline()[1:].strip())
    value = None if size < 0 else f.read(size)
    if size >= 0: f.read(2)
    s.close()
    return None if value is None else value.decode()

assert redis_get('sensor_chunks:' + sensor) == '3'
base = f'/home/user/processed/{sensor}'
assert set(os.listdir(base)) == {'chunk_0.bin', 'chunk_1.bin', 'chunk_2.bin'}
for i in range(3):
    expected = data[i*1_000_000:(i+1)*1_000_000]
    path = f'{base}/chunk_{i}.bin'
    assert stat.S_ISREG(os.lstat(path).st_mode)
    assert open(path, 'rb').read() == expected
    assert get(f'http://127.0.0.1:8090/api/data/{sensor}/chunk/{i}') == expected
assert get(f'http://127.0.0.1:8090/api/data/{sensor}/meta') == meta.encode()
PY
stop_pid "$CHALLENGE_PID"

# Restore the real archive, force the compiled artifact to regenerate all
# outputs, and retain and expand the original fixed assertions.
restore_dataset
rm -rf /home/user/processed
mkdir -p /home/user/processed
redis-cli -h 127.0.0.1 -p 6379 DEL sensor_chunks:sensor_alpha sensor_chunks:sensor_beta >/dev/null
kill_port_8080
/tmp/submitted_sensor_server >/tmp/final-server.log 2>&1 &
FINAL_PID=$!
wait_for_api

python3 - <<'PY'
import io, os, socket, stat, tarfile, urllib.error, urllib.request, zipfile

def redis_get(key):
    try:
        s = socket.create_connection(('127.0.0.1', 6379), 2)
        f = s.makefile('rb')
        b = key.encode()
        s.sendall(b'*2\r\n$3\r\nGET\r\n$%d\r\n%s\r\n' % (len(b), b))
        first = f.readline()
        if not first.startswith(b'$'):
            return None
        size = int(first[1:].strip())
        if size < 0:
            return None
        value = f.read(size)
        f.read(2)
        s.close()
        return value.decode()
    except Exception:
        return None

def get(path):
    with urllib.request.urlopen('http://127.0.0.1:8090' + path, timeout=3) as r:
        assert r.status == 200
        return r.read()

sensors = {}
with tarfile.open('/app/dataset.tar.gz', 'r:gz') as tar:
    for member in tar.getmembers():
        if not member.isfile() or not member.name.endswith('.zip'):
            continue
        raw_zip = tar.extractfile(member).read()
        with zipfile.ZipFile(io.BytesIO(raw_zip)) as z:
            names = z.namelist()
            meta_name = next(n for n in names if n.endswith('/meta.txt') or n == 'meta.txt')
            data_name = next(n for n in names if n.endswith('/data.bin') or n == 'data.bin')
            sensor = os.path.basename(member.name)[:-4]
            sensors[sensor] = (z.read(meta_name), z.read(data_name))

# Original Redis assertions.
assert redis_get('sensor_chunks:sensor_alpha') == '3'
assert redis_get('sensor_chunks:sensor_beta') == '2'

# Original metadata assertions, plus exact-byte validation.
alpha_meta = get('/api/data/sensor_alpha/meta')
assert alpha_meta.decode().strip() == 'Alpha-v1.2 active'
beta_meta = get('/api/data/sensor_beta/meta')
assert beta_meta.decode().strip() == 'Beta-v2.0 inactive'
assert alpha_meta == sensors['sensor_alpha'][0]
assert beta_meta == sensors['sensor_beta'][0]

# Original chunk-1 assertions.
assert get('/api/data/sensor_alpha/chunk/1') == sensors['sensor_alpha'][1][1_000_000:2_000_000]
assert get('/api/data/sensor_beta/chunk/1') == sensors['sensor_beta'][1][1_000_000:2_000_000]

# Validate every generated chunk, including chunk zero and final short chunks,
# both on disk and through the Nginx gateway.
assert set(os.listdir('/home/user/processed')) == set(sensors)
for sensor, (meta, data) in sensors.items():
    chunks = [data[i:i+1_000_000] for i in range(0, len(data), 1_000_000)]
    assert redis_get('sensor_chunks:' + sensor) == str(len(chunks))
    directory = f'/home/user/processed/{sensor}'
    expected_names = {f'chunk_{i}.bin' for i in range(len(chunks))}
    assert set(os.listdir(directory)) == expected_names
    for i, expected in enumerate(chunks):
        path = f'{directory}/chunk_{i}.bin'
        assert stat.S_ISREG(os.lstat(path).st_mode)
        assert os.path.getsize(path) == len(expected)
        assert open(path, 'rb').read() == expected
        assert get(f'/api/data/{sensor}/chunk/{i}') == expected
    assert get(f'/api/data/{sensor}/meta') == meta

# No temporary or unexpected files may remain in the processed tree.
for root, dirs, files in os.walk('/home/user/processed'):
    for name in dirs + files:
        assert 'tmp' not in name.lower() and 'temp' not in name.lower(), (root, name)
PY

# Ensure the process we launched from the compiled server.go artifact remains
# active and owns the direct Go API listener at the end of verification.
kill -0 "$FINAL_PID"
)

if run_verifier > /tmp/verifier-output.log 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    cat /tmp/verifier-output.log 2>/dev/null || true
    echo "0" > /logs/verifier/reward.txt
fi
