#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ curl wget
pip3 install pytest

python3 -c "
import os
import urllib.request

# Create directories
dirs = [
    '/home/user/project_root/logs',
    '/home/user/project_root/config',
    '/home/user/project_root/src/core',
    '/home/user/project_root/src/backend',
    '/home/user/project_root/src/frontend',
    '/home/user/project_root/src/physics',
    '/home/user/workspace',
    '/home/user/libs'
]
for d in dirs:
    os.makedirs(d, exist_ok=True)

# Download nlohmann json
json_url = 'https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp'
urllib.request.urlretrieve(json_url, '/home/user/libs/json.hpp')

# Create C++ files
files_content = {
    '/home/user/project_root/src/core/logger.cpp': '/* TODO: UPDATE_LICENSE */\\nvoid log() {}',
    '/home/user/project_root/src/backend/db.cpp': '/* TODO: UPDATE_LICENSE */\\nvoid query() {}',
    '/home/user/project_root/src/backend/net.cpp': '/* OLD_LICENSE */\\nvoid connect() {\\n  syntax error\\n}',
    '/home/user/project_root/src/frontend/render.cpp': '/* TODO: UPDATE_LICENSE */\\nvoid draw() {}',
    '/home/user/project_root/src/physics/phys.cpp': '/* OLD_LICENSE */\\nvoid collide() {\\n  undefined_var = 1;\\n}'
}

for path, content in files_content.items():
    with open(path, 'w') as f:
        f.write(content)

# Create JSON registry
registry_json = \"\"\"{
  \"project\": \"SuperApp\",
  \"version\": \"1.0.0\",
  \"components\": {
    \"Logger\": \"logger.cpp\",
    \"Database\": \"db.cpp\",
    \"Network\": \"net.cpp\",
    \"Renderer\": \"render.cpp\",
    \"PhysicsEngine\": \"phys.cpp\"
  }
}\"\"\"
with open('/home/user/project_root/config/registry.json', 'w') as f:
    f.write(registry_json)

# Create build log
build_log = \"\"\"
Building project...
[ 20%] Building CXX object src/core/logger.cpp.o
[ 40%] Building CXX object src/backend/db.cpp.o
[ 60%] Building CXX object src/backend/net.cpp.o
/home/user/project_root/src/backend/net.cpp: In function 'void connect()':
/home/user/project_root/src/backend/net.cpp:3:3: error: expected ';' before '}' token
    3 |   syntax error
      |   ^
[ 80%] Building CXX object src/frontend/render.cpp.o
[100%] Building CXX object src/physics/phys.cpp.o
/home/user/project_root/src/physics/phys.cpp: In function 'void collide()':
/home/user/project_root/src/physics/phys.cpp:3:3: fatal error: 'undefined_var' was not declared in this scope
    3 |   undefined_var = 1;
      |   ^~~~~~~~~~~~~
Compilation failed.
\"\"\"
with open('/home/user/project_root/logs/build.log', 'w') as f:
    f.write(build_log)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
