#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ci_artifacts

    cat << 'EOF' > /home/user/ci_artifacts/link_error.log
[100%] Linking CXX executable my_app
/usr/bin/ld: CMakeFiles/my_app.dir/main.cpp.o: in function `main':
main.cpp:(.text+0x10): undefined reference to `init_math()'
/usr/bin/ld: cannot find -lmathutils
/usr/bin/ld: cannot find -lcoreengine
/usr/bin/ld: cannot find -lnetstack
/usr/bin/ld: cannot find -lcorruptedlib
collect2: error: ld returned 1 exit status
make[2]: *** [CMakeFiles/my_app.dir/build.make:112: my_app] Error 1
EOF

    cat << 'EOF' > /home/user/ci_artifacts/registry.dat
6d6174687574696c73:L29wdC9jaV9jYWNoZS9saWJtYXRodXRpbHMuc28=:97fdf41bc568d4078de3d0d8296a605f
636f7265656e67696e65:L3Vzci9sb2NhbC9saWIvbGliY29yZWVuZ2luZS5zbw==:72851494541dc8aed318c6444b0e5ee0
6e6574737461636b:L29wdC9uZXR3b3JrL2xpYm5ldHN0YWNrLnNv:ac0dbb121fb69abf8b80ebbe518e38cb
636f727275707465646c6962:L2JhZC9wYXRoL2xpYmNvcnJ1cHRlZC5zbw==:00000000000000000000000000000000
756e72ZWxhdGVk:L3RtcC9saWJ1bnJlbGF0ZWQuc28=:d41d8cd98f00b204e9800998ecf8427e
EOF

    chmod -R 777 /home/user
