#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user/vulnerable_app/views

cat << 'EOF' > /home/user/vulnerable_app/rbac.json
{
  "roles": [
    {"name": "guest", "can_sudo": false},
    {"name": "developer", "can_sudo": true},
    {"name": "admin", "can_sudo": true},
    {"name": "ci_runner", "can_sudo": true}
  ]
}
EOF

cat << 'EOF' > /home/user/vulnerable_app/db.go
package main
import "fmt"
func getUser(user string) string {
    return fmt.Sprintf("SELECT * FROM users WHERE username='%s'", user)
}
EOF

# Use python to write the file to avoid Apptainer build variable syntax errors
python3 -c "print('<html>\n<body>\n  <div>Welcome, {' + '{.Username}' + '}</div>\n</body>\n</html>')" > /home/user/vulnerable_app/views/index.html

cat << 'EOF' > /home/user/vulnerable_app/secrets.txt
DatabaseURL=postgres://user:pass@localhost:5432/db
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
SomeOtherKey=AKIA1234567890ABCDEF
EOF

cat << 'EOF' > /home/user/vulnerable_app/threats.txt
192.168.1.50
10.0.0.5
203.0.113.42
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
