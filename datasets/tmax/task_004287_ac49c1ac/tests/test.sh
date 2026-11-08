#!/bin/bash
set -u
mkdir -p /logs/verifier /tmp/ffmpeg_inputs /tmp/transcribe_inputs
rm -f /logs/verifier/reward.txt /home/user/metrics.txt /tmp/ffmpeg_calls.log /tmp/transcribe_calls.log /tmp/text2vec_calls.log /tmp/pipeline_rc

REAL_FFMPEG=/usr/bin/ffmpeg
BACKUP_FFMPEG=/usr/bin/ffmpeg.verifier-real
BACKUP_TRANSCRIBE=/app/tools/transcribe.verifier-real
BACKUP_TEXT2VEC=/app/tools/text2vec.verifier-real

cleanup() {
    if [ -e "$BACKUP_FFMPEG" ]; then mv -f "$BACKUP_FFMPEG" "$REAL_FFMPEG"; fi
    if [ -e "$BACKUP_TRANSCRIBE" ]; then mv -f "$BACKUP_TRANSCRIBE" /app/tools/transcribe; fi
    if [ -e "$BACKUP_TEXT2VEC" ]; then mv -f "$BACKUP_TEXT2VEC" /app/tools/text2vec; fi
}
trap cleanup EXIT

# Install logging wrappers around the actual tools so the submitted pipeline is
# exercised rather than trusting a pre-written metrics file.
mv "$REAL_FFMPEG" "$BACKUP_FFMPEG"
cat > "$REAL_FFMPEG" <<'WRAP'
#!/bin/bash
real=/usr/bin/ffmpeg.verifier-real
id="$(date +%s%N)-$$-$RANDOM"
{
  printf 'CALL\t%s' "$id"
  printf '\t%s' "$@"
  printf '\n'
} >> /tmp/ffmpeg_calls.log
prev=''
for arg in "$@"; do
  if [ "$prev" = '-i' ] && [ -f "$arg" ]; then
    snap="/tmp/ffmpeg_inputs/${id}-$(basename "$arg")"
    cp "$arg" "$snap" 2>/dev/null || true
    printf 'SNAP\t%s\t%s\t%s\n' "$id" "$arg" "$snap" >> /tmp/ffmpeg_calls.log
  fi
  prev="$arg"
done
exec "$real" "$@"
WRAP
chmod +x "$REAL_FFMPEG"

mv /app/tools/transcribe "$BACKUP_TRANSCRIBE"
cat > /app/tools/transcribe <<'WRAP'
#!/bin/bash
id="$(date +%s%N)-$$-$RANDOM"
input="${1:-}"
snap=''
if [ -f "$input" ]; then
  snap="/tmp/transcribe_inputs/${id}-$(basename "$input")"
  cp "$input" "$snap"
fi
printf '%s\t%s\t%s\n' "$id" "$input" "$snap" >> /tmp/transcribe_calls.log
exec /app/tools/transcribe.verifier-real "$@"
WRAP
chmod +x /app/tools/transcribe

mv /app/tools/text2vec "$BACKUP_TEXT2VEC"
cat > /app/tools/text2vec <<'WRAP'
#!/bin/bash
printf 'CALL' >> /tmp/text2vec_calls.log
printf '\t%s' "$@" >> /tmp/text2vec_calls.log
printf '\n' >> /tmp/text2vec_calls.log
exec /app/tools/text2vec.verifier-real "$@"
WRAP
chmod +x /app/tools/text2vec

# Remove stale experiment products and provide a challenge recording. The first
# four 10-second windows are quiet 440 Hz training audio; the final window is a
# much louder 880 Hz test signal. A global-volume implementation therefore has
# observably different behavior from train-only normalization.
find /app/experiment -mindepth 1 -maxdepth 1 ! -name interview.wav ! -name ground_truth -exec rm -rf {} +
rm -rf /app/experiment/ground_truth
mkdir -p /app/experiment/ground_truth
"$BACKUP_FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i 'aevalsrc=if(lt(t\,40)\,0.05*sin(2*PI*440*t)\,0.20*sin(2*PI*880*t)):s=16000:d=50' \
  -ac 1 -ar 16000 /app/experiment/interview.wav

# Derive a fresh ground-truth vector. Its cosine with text2vec's [0.1,0.2,0.3]
# remains inside the original 0.824 +/- 0.05 assertion, but is not a fixed value
# that can be safely self-reported.
python3 <<'PY'
import json, math, os, secrets
c = 0.800 + secrets.randbelow(4001) / 100000.0
u0 = [0.1, 0.2, 0.3]
n = math.sqrt(sum(x*x for x in u0))
u = [x/n for x in u0]
w0 = [0.2, -0.1, 0.0]
wn = math.sqrt(sum(x*x for x in w0))
w = [x/wn for x in w0]
s = math.sqrt(1.0-c*c)
g = [c*u[i] + s*w[i] for i in range(3)]
with open('/tmp/expected_similarity', 'w') as f:
    f.write(repr(c))
# Common naming conventions are supplied because the original image omitted
# the promised fixture entirely. All aliases represent the same test segment.
names = [
    'segment_004.json', 'segment_4.json', 'test_000.json', 'test_0.json',
    'normalized_segment_004.json', 'segment_004.embedding',
    'segment_004.txt'
]
for name in names:
    with open('/app/experiment/ground_truth/' + name, 'w') as f:
        json.dump({'embedding': g}, f)
PY

# Run the submitted artifact from a clean state.
timeout 120 bash /home/user/pipeline.sh >/tmp/pipeline_stdout.log 2>/tmp/pipeline_stderr.log
printf '%s\n' "$?" > /tmp/pipeline_rc

cat > /tmp/test_final_state.py <<'PY'
import json
import math
import os
import re
import subprocess
import wave
import pytest

REAL_FFMPEG = '/usr/bin/ffmpeg.verifier-real'

def test_pipeline_script_exists():
    assert os.path.isfile('/home/user/pipeline.sh'), 'The script /home/user/pipeline.sh does not exist.'
    assert os.access('/home/user/pipeline.sh', os.R_OK), 'pipeline.sh is not readable.'

def test_pipeline_executed_successfully():
    assert os.path.isfile('/tmp/pipeline_rc')
    assert open('/tmp/pipeline_rc').read().strip() == '0', 'bash /home/user/pipeline.sh did not complete successfully.'

def test_metrics_file_exists():
    assert os.path.isfile('/home/user/metrics.txt'), 'The file /home/user/metrics.txt does not exist.'

def read_metric():
    content = open('/home/user/metrics.txt').read().strip()
    m = re.fullmatch(r'Test_Similarity:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)', content)
    assert m, "The format 'Test_Similarity: <score>' was not found in metrics.txt."
    score = float(m.group(1))
    assert math.isfinite(score)
    return score

def test_metric_threshold():
    agent_score = read_metric()
    target_score = 0.824
    error = abs(agent_score - target_score)
    tolerance = 0.05
    assert error <= tolerance, f'Metric threshold failed: Agent score {agent_score} is not within {tolerance} of target {target_score} (Error: {error})'

def test_metric_is_computed_from_challenge_ground_truth():
    expected = float(open('/tmp/expected_similarity').read())
    actual = read_metric()
    assert abs(actual - expected) <= 0.01, f'Reported similarity {actual} does not match the challenge embeddings ({expected}).'

def parse_ffmpeg_log():
    calls, snaps = {}, {}
    if not os.path.exists('/tmp/ffmpeg_calls.log'):
        return calls, snaps
    for line in open('/tmp/ffmpeg_calls.log', errors='replace'):
        fields = line.rstrip('\n').split('\t')
        if fields[0] == 'CALL' and len(fields) >= 2:
            calls[fields[1]] = fields[2:]
        elif fields[0] == 'SNAP' and len(fields) == 4:
            snaps.setdefault(fields[1], []).append((fields[2], fields[3]))
    return calls, snaps

def signal_info(path):
    out = '/tmp/probe-%d-%d.wav' % (os.getpid(), abs(hash(path)) % 100000000)
    subprocess.run([REAL_FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-i', path,
                    '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', out], check=True)
    with wave.open(out, 'rb') as w:
        rate = w.getframerate()
        frames = w.getnframes()
        raw = w.readframes(frames)
    os.unlink(out)
    vals = [int.from_bytes(raw[i:i+2], 'little', signed=True) for i in range(0, len(raw), 2)]
    duration = len(vals) / rate
    usable = vals[rate//10:] if len(vals) > rate//10 else vals
    crossings = sum((a < 0) != (b < 0) for a, b in zip(usable, usable[1:]))
    freq = crossings * rate / (2.0 * max(1, len(usable)-1))
    clipped = sum(abs(v) >= 32760 for v in usable) / max(1, len(usable))
    return duration, freq, clipped

def extract_inputs(args):
    return [args[i+1] for i, a in enumerate(args[:-1]) if a == '-i']

def test_split_then_train_only_volume_detection_and_uniform_gain():
    calls, snaps = parse_ffmpeg_log()
    assert calls, 'The pipeline did not invoke ffmpeg.'

    detect_ids = [cid for cid, args in calls.items() if any('volumedetect' in a for a in args)]
    assert detect_ids, 'No max-volume measurement was performed.'
    for cid in detect_ids:
        inputs = extract_inputs(calls[cid])
        assert '/app/experiment/interview.wav' not in inputs, 'max_volume was measured from the complete interview before splitting.'
        for _, snap in snaps.get(cid, []):
            duration, freq, _ = signal_info(snap)
            assert freq < 650, 'A test segment was included in max_volume computation.'

    gain_calls = []
    gain_values = []
    for cid, args in calls.items():
        joined = ' '.join(args)
        if 'volume=' in joined and 'volumedetect' not in joined:
            gain_calls.append(cid)
            gain_values.extend(re.findall(r'volume\s*=\s*([^,;\]\s]+)', joined))
    assert len(gain_calls) >= 5, 'Expected every one of the five split segments to be normalized independently.'
    assert gain_values, 'No explicit volume gain was applied to split segments.'
    assert len(set(gain_values)) == 1, 'The same train-derived gain factor was not used for every train and test segment.'

    classified = []
    for cid in gain_calls:
        for _, snap in snaps.get(cid, []):
            duration, freq, _ = signal_info(snap)
            if 8.0 <= duration <= 11.0:
                classified.append(freq)
    assert sum(350 <= f <= 550 for f in classified) >= 4, 'The first four numeric 10-second train segments were not normalized independently.'
    assert sum(750 <= f <= 1000 for f in classified) >= 1, 'The final numeric 10-second test segment was not normalized independently.'

def test_only_normalized_test_audio_is_transcribed_and_embedded():
    assert os.path.isfile('/tmp/transcribe_calls.log'), 'The transcription tool was never run.'
    rows = [line.rstrip('\n').split('\t') for line in open('/tmp/transcribe_calls.log') if line.strip()]
    assert rows
    for row in rows:
        assert len(row) >= 3 and row[2] and os.path.isfile(row[2]), 'Transcription input was not an audio file.'
        duration, freq, clipped = signal_info(row[2])
        assert 8.0 <= duration <= 11.0, 'Transcription was not run on a 10-second segment.'
        assert 750 <= freq <= 1000, 'A train segment was transcribed, or the numeric train/test split is wrong.'
        assert clipped > 0.25, 'Test audio does not carry the gain derived solely from the quieter training segments.'
    assert os.path.isfile('/tmp/text2vec_calls.log'), 'The embedding tool was never run.'
    embedding_calls = sum(1 for line in open('/tmp/text2vec_calls.log') if line.startswith('CALL'))
    assert embedding_calls >= len(rows), 'An embedding was not extracted for each transcribed test segment.'
PY

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
