#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq dos2unix make gawk
pip3 install pytest

mkdir -p /app/json2csv-schema-1.2
mkdir -p /home/user/.local/bin

cat << 'EOF' > /home/user/raw_experiments.jsonl
{"artifact_id": "ART-101", "run_id": "r1", "status": "SUCCESS", "latency_ms": 45}
{"artifact_id": "ART-101", "run_id": "r2", "status": "SUCCESS", "latency_ms": 55}
{"artifact_id": "ART-101", "run_id": "r3", "status": "FAILED", "latency_ms": 40}
{"artifact_id": "ART-102", "run_id": "r4", "status": "SUCCESS", "latency_ms": 100}
{"artifact_id": "ART-102", "run_id": "r5", "status": "SUCCESS", "latency_ms": 90}
{"artifact_id": "ART-103", "run_id": "r6", "status": "SUCCESS", "latency_ms": 10}
EOF

cat << 'EOF' > /app/json2csv-schema-1.2/Makefile
install:
	mkdir -p $(PREFIX)/bin
	cp json2csv.sh $(PREFX)/bin/json2csv
EOF

cat << 'EOF' > /app/json2csv-schema-1.2/json2csv.sh
#!/bin/bash
if [ "$ENFORCE_STRICT_SCHEMA" != "1" ]; then
  echo "Error: Strict schema not enforced." >&2
  exit 1
fi
echo "artifact_id,run_id,status,latency_ms"
jq -r '[.artifact_id, .run_id, .status, .latency_ms] | @csv' "$1" | tr -d '"'
EOF

unix2dos /app/json2csv-schema-1.2/json2csv.sh
chmod 644 /app/json2csv-schema-1.2/json2csv.sh

cat << 'EOF' > /app/oracle_benchmark.sh
#!/bin/bash
ART=$1
LAT=$2
AWK_SCRIPT='
BEGIN { FS=","; s=0; f=0 }
$1 == art {
    if ($3 == "SUCCESS" && $4 <= lat) { s++ }
    else { f++ }
}
END {
    mean = (2 + s) / (4 + s + f)
    printf "%.4f\n", mean
}
'
awk -v art="$ART" -v lat="$LAT" "$AWK_SCRIPT" /home/user/artifacts.csv
EOF
chmod +x /app/oracle_benchmark.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
