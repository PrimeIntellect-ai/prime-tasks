#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential wget curl
pip3 install pytest websockets

mkdir -p /app/vendored/mongoose
mkdir -p /app/corpus/evil
mkdir -p /app/corpus/clean

# Download mongoose 7.11
wget https://github.com/cesanta/mongoose/archive/refs/tags/7.11.tar.gz -O /tmp/mongoose.tar.gz
tar -xzf /tmp/mongoose.tar.gz -C /tmp
cp /tmp/mongoose-7.11/mongoose.c /app/vendored/mongoose/
cp /tmp/mongoose-7.11/mongoose.h /app/vendored/mongoose/
rm -rf /tmp/mongoose.tar.gz /tmp/mongoose-7.11

# Create perturbed Makefile
cat << 'EOF' > /app/vendored/mongoose/Makefile
all:
	$(CC) -shared -fPIC mongoose.c -o libmongoose.so
EOF

# Create corpus
for i in $(seq 1 10); do
    if [ $((i % 2)) -eq 0 ]; then
        echo "<script>alert($i)</script>" > /app/corpus/evil/payload_$i.txt
    else
        echo "SELECT *; DROP TABLE users; -- $i" > /app/corpus/evil/payload_$i.txt
    fi
    echo "{\"data\": \"clean telemetry $i\"}" > /app/corpus/clean/payload_$i.txt
done

# Create bench tool
cat << 'EOF' > /app/bench_tool.sh
#!/bin/bash
echo "Benchmarking ws://localhost:8080..."
echo "Sent 500 messages."
echo "Latency: 2ms avg."
echo "Throughput: 1000 msg/sec."
EOF
chmod +x /app/bench_tool.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
