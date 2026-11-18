#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/cargo_logs.jsonl
{"reason":"compiler-artifact","package_id":"my-app 0.1.0 (path+file:///app)","target":{"kind":["bin"],"crate_types":["bin"],"name":"my-app","src_path":"/app/src/main.rs","edition":"2021"},"profile":{"opt_level":"0","debuginfo":2,"debug_assertions":true,"overflow_checks":true,"test":false},"features":[],"filenames":["/app/target/debug/my-app"],"executable":null,"fresh":false}
{"reason":"compiler-message","package_id":"my-app 0.1.0 (path+file:///app)","target":{"kind":["bin"],"crate_types":["bin"],"name":"my-app","src_path":"/app/src/main.rs","edition":"2021"},"message":{"rendered":"error[E0382]: use of moved value: `s`\n","children":[],"code":{"code":"E0382","explanation":null},"level":"error","message":"use of moved value: `s`","spans":[{"byte_end":124,"byte_start":123,"column_end":23,"column_start":22,"file_name":"src/main.rs","is_primary":true,"label":"value used here after move","line_end":5,"line_start":5,"mac":null,"suggested_replacement":null,"suggestion_applicability":null,"text":[{"highlight_end":23,"highlight_start":22,"text":"    println!(\"{}\", s);"}],"expansion":null}]}}
{"reason":"compiler-message","package_id":"my-app 0.1.0 (path+file:///app)","target":{"kind":["bin"],"crate_types":["bin"],"name":"my-app","src_path":"/app/src/main.rs","edition":"2021"},"message":{"rendered":"error[E0499]: cannot borrow `x` as mutable more than once at a time\n","children":[],"code":{"code":"E0499","explanation":null},"level":"error","message":"cannot borrow `x` as mutable more than once at a time","spans":[{"byte_end":124,"byte_start":123,"column_end":23,"column_start":22,"file_name":"src/lib.rs","is_primary":true,"label":"second mutable borrow occurs here","line_end":10,"line_start":10,"mac":null,"suggested_replacement":null,"suggestion_applicability":null,"text":[{"highlight_end":23,"highlight_start":22,"text":"    let y = &mut x;"}],"expansion":null}]}}
{"reason":"compiler-message","package_id":"my-app 0.1.0 (path+file:///app)","target":{"kind":["bin"],"crate_types":["bin"],"name":"my-app","src_path":"/app/src/main.rs","edition":"2021"},"message":{"rendered":"error[E0382]: use of moved value: `config`\n","children":[],"code":{"code":"E0382","explanation":null},"level":"error","message":"use of moved value: `config`","spans":[{"byte_end":124,"byte_start":123,"column_end":23,"column_start":22,"file_name":"src/config.rs","is_primary":true,"label":"value used here after move","line_end":42,"line_start":42,"mac":null,"suggested_replacement":null,"suggestion_applicability":null,"text":[{"highlight_end":23,"highlight_start":22,"text":"    let z = config;"}],"expansion":null}]}}
EOF

chmod -R 777 /home/user
