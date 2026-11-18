#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
HEADERS = {"X-Bio-Auth": "secret-token-77"}

def test_unauthorized():
    """Test that requests without the correct auth header return 401."""
    try:
        response = requests.get(f"{BASE_URL}/slope/0/0", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"

@pytest.mark.parametrize("x, y, expected_slope", [
    (0, 0, "10.00"),
    (1, 0, "20.00"),
    (0, 1, "5.00"),
    (1, 1, "0.00"),
])
def test_slope_endpoints(x, y, expected_slope):
    """Test that authenticated requests return the correct slope."""
    try:
        response = requests.get(f"{BASE_URL}/slope/{x}/{y}", headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert response.status_code == 200, f"Expected 200 OK for /slope/{x}/{y}, got {response.status_code}"

    actual_slope = response.text.strip()
    assert actual_slope == expected_slope, f"Expected slope {expected_slope} for /slope/{x}/{y}, got '{actual_slope}'"
TEST_EOF

run_dynamic_test() {
    [ -f /home/user/serve_results.sh ] || return 1
    [ ! -L /home/user/serve_results.sh ] || return 1

    cp /app/microarray_signal.mp4 /tmp/original_microarray_signal.mp4 || return 1
    rm -rf /tmp/verifier_video /tmp/verifier_decoded /tmp/verifier_values.tsv /tmp/verifier_expected.tsv
    mkdir -p /tmp/verifier_video /tmp/verifier_decoded || return 1

    local r n b00 b10 b01 b11 s00 s10 s01 s11 i v00 v10 v01 v11
    r=$(od -An -N2 -tu2 /dev/urandom)
    n=$((7 + r % 5))
    r=$(od -An -N2 -tu2 /dev/urandom); b00=$((20 + r % 21))
    r=$(od -An -N2 -tu2 /dev/urandom); b10=$((15 + r % 21))
    r=$(od -An -N2 -tu2 /dev/urandom); b01=$((175 + r % 26))
    r=$(od -An -N2 -tu2 /dev/urandom); b11=$((45 + r % 31))
    r=$(od -An -N2 -tu2 /dev/urandom); s00=$((3 + r % 7))
    r=$(od -An -N2 -tu2 /dev/urandom); s10=$((11 + r % 7))
    r=$(od -An -N2 -tu2 /dev/urandom); s01=$((-3 - r % 6))
    r=$(od -An -N2 -tu2 /dev/urandom); s11=$((1 + r % 6))

    for i in $(seq 1 "$n"); do
        v00=$((b00 + i * s00))
        v10=$((b10 + i * s10))
        v01=$((b01 + i * s01))
        v11=$((b11 + i * s11))
        printf 'P2\n2 2\n255\n%d %d\n%d %d\n' "$v00" "$v10" "$v01" "$v11" > /tmp/verifier_video/grid.pgm || return 1
        convert /tmp/verifier_video/grid.pgm -scale 100x100 "/tmp/verifier_video/frame_$(printf '%04d' "$i").png" || return 1
    done

    ffmpeg -loglevel error -y -framerate 1 -i /tmp/verifier_video/frame_%04d.png -c:v libx264 -pix_fmt yuv420p /app/microarray_signal.mp4 || return 1
    ffmpeg -loglevel error -y -i /app/microarray_signal.mp4 /tmp/verifier_decoded/frame_%04d.png || return 1

    : > /tmp/verifier_values.tsv
    i=0
    for f in /tmp/verifier_decoded/frame_*.png; do
        [ -f "$f" ] || return 1
        i=$((i + 1))
        for y in 0 1; do
            for x in 0 1; do
                value=$(convert "$f" -colorspace Gray -resize '2x2!' -depth 8 -format "%[fx:round(255*p{$x,$y}.r)]" info:) || return 1
                printf '%d\t%d\t%d\t%s\n' "$x" "$y" "$i" "$value" >> /tmp/verifier_values.tsv
            done
        done
    done
    [ "$i" -eq "$n" ] || return 1

    awk '
    {
        key=$1 "," $2
        count[key]++
        sx[key]+=$3
        sy[key]+=$4
        sxx[key]+=$3*$3
        sxy[key]+=$3*$4
    }
    END {
        for (key in count) {
            m=(count[key]*sxy[key]-sx[key]*sy[key])/(count[key]*sxx[key]-sx[key]*sx[key])
            if (m > -0.005 && m < 0.005) m=0
            split(key, p, ",")
            printf "%s\t%s\t%.2f\n", p[1], p[2], m
        }
    }' /tmp/verifier_values.tsv | sort > /tmp/verifier_expected.tsv || return 1

    pkill -f '[s]erve_results.sh' 2>/dev/null || true
    pkill -x socat 2>/dev/null || true
    pkill -x nc 2>/dev/null || true
    sleep 1

    (cd /home/user && bash ./serve_results.sh) >/tmp/verifier_server.log 2>&1 &

    local ready=0 code body expected x y attempt
    for attempt in $(seq 1 30); do
        code=$(curl -sS --max-time 1 -o /tmp/verifier_probe_body -w '%{http_code}' http://127.0.0.1:9090/slope/0/0 2>/dev/null)
        if [ "$code" = "401" ]; then
            ready=1
            break
        fi
        sleep 0.5
    done
    [ "$ready" -eq 1 ] || return 1

    code=$(curl -sS --max-time 5 -o /tmp/verifier_bad_auth_body -w '%{http_code}' -H 'X-Bio-Auth: wrong-token' http://127.0.0.1:9090/slope/0/0) || return 1
    [ "$code" = "401" ] || return 1

    while IFS=$'\t' read -r x y expected; do
        code=$(curl -sS --max-time 5 -o /tmp/verifier_response_body -w '%{http_code}' -H 'X-Bio-Auth: secret-token-77' "http://127.0.0.1:9090/slope/$x/$y") || return 1
        [ "$code" = "200" ] || return 1
        body=$(cat /tmp/verifier_response_body)
        [ "$body" = "$expected" ] || return 1
    done < /tmp/verifier_expected.tsv

    return 0
}

original_ok=0
artifact_ok=0
dynamic_ok=0

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && original_ok=1
[ -f /home/user/serve_results.sh ] && [ ! -L /home/user/serve_results.sh ] && artifact_ok=1
run_dynamic_test && dynamic_ok=1

if [ -f /tmp/original_microarray_signal.mp4 ]; then
    cp /tmp/original_microarray_signal.mp4 /app/microarray_signal.mp4
fi

if [ "$original_ok" -eq 1 ] && [ "$artifact_ok" -eq 1 ] && [ "$dynamic_ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
