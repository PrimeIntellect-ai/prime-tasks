#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip patch gawk
pip3 install pytest

mkdir -p /home/user/qa

cat << 'EOF' > /home/user/qa/test_runner.sh
#!/bin/bash
echo "[NOISE] Initializing tests..."
echo ">>> START COMPONENT: C_Core"
echo "Iteration: 5ms"
echo "[NOISE] cache miss"
echo "Iteration: 4ms"
echo "Iteration: 6ms"
echo "<<< FINISH COMPONENT"

echo "Random noise outside blocks"

echo ">>> START COMPONENT: Python_Worker"
echo "[NOISE] Warming up JIT..."
echo "Iteration: 45ms"
echo "Iteration: 42ms"
echo "<<< FINISH COMPONENT"

echo ">>> START COMPONENT: Go_Service"
echo "Iteration: 12ms"
echo "Iteration: 11ms"
echo "Iteration: 10ms"
echo "<<< FINISH COMPONENT"
EOF

chmod +x /home/user/qa/test_runner.sh

cat << 'EOF' > /home/user/qa/fix_runner.patch
--- test_runner.sh	2023-10-25 10:00:00.000000000 +0000
+++ test_runner_fixed.sh	2023-10-25 10:05:00.000000000 +0000
@@ -6,14 +6,14 @@
 echo "[NOISE] cache miss"
 echo "Iteration: 4ms"
 echo "Iteration: 6ms"
-echo "<<< FINISH COMPONENT"
+echo "<<< END COMPONENT"

 echo "Random noise outside blocks"

 echo ">>> START COMPONENT: Python_Worker"
 echo "[NOISE] Warming up JIT..."
 echo "Iteration: 45ms"
 echo "Iteration: 42ms"
-echo "<<< FINISH COMPONENT"
+echo "<<< END COMPONENT"

 echo ">>> START COMPONENT: Go_Service"
 echo "Iteration: 12ms"
 echo "Iteration: 11ms"
 echo "Iteration: 10ms"
-echo "<<< FINISH COMPONENT"
+echo "<<< END COMPONENT"
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
