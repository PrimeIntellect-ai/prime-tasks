#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg protobuf-compiler
pip3 install pytest protobuf==3.20.3

mkdir -p /app/schema
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil
mkdir -p /app/eval_corpus/clean
mkdir -p /app/eval_corpus/evil

cat << 'EOF' > /app/schema/video_events.proto
syntax = "proto3";
message Event {
  int64 start_time_ms = 1;
  int64 end_time_ms = 2;
  string event_type = 3;
}
message VideoEventLog {
  repeated Event events = 1;
}
EOF

protoc -I/app/schema --python_out=/app/schema /app/schema/video_events.proto

cat << 'EOF' > /tmp/gen_protos.py
import sys
sys.path.append('/app/schema')
import video_events_pb2

def write_log(path, events):
    log = video_events_pb2.VideoEventLog()
    for e in events:
        evt = log.events.add()
        evt.start_time_ms = e[0]
        evt.end_time_ms = e[1]
        evt.event_type = e[2]
    with open(path, 'wb') as f:
        f.write(log.SerializeToString())

# clean
write_log('/app/corpus/clean/1.bin', [(0, 10, 'A'), (10, 20, 'B')])
write_log('/app/eval_corpus/clean/1.bin', [(5, 15, 'A'), (20, 30, 'B')])

# evil
write_log('/app/corpus/evil/1.bin', [(-1, 10, 'A')]) # negative start
write_log('/app/corpus/evil/2.bin', [(10, 10, 'A')]) # zero duration
write_log('/app/corpus/evil/3.bin', [(10, 5, 'A')]) # negative duration
write_log('/app/corpus/evil/4.bin', [(0, 10, 'A'), (5, 15, 'B')]) # overlap
write_log('/app/eval_corpus/evil/1.bin', [(-5, 5, 'A')])
write_log('/app/eval_corpus/evil/2.bin', [(0, 10, 'A'), (10, 20, 'B'), (15, 25, 'C')])
EOF

python3 /tmp/gen_protos.py

ffmpeg -f lavfi -i color=c=black:s=320x240:d=2 -vcodec libx264 -pix_fmt yuv420p /app/reference_video.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
