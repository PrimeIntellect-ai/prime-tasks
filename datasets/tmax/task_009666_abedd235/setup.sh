#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/infra.ttl
@prefix ex: <http://example.org/> .

ex:Server1 ex:runs ex:SoftwareA .
ex:Server2 ex:runs ex:SoftwareB .
ex:Server3 ex:runs ex:SoftwareA .

ex:Alice ex:accesses ex:Server1 .
ex:Bob ex:accesses ex:Server2 .
ex:Charlie ex:accesses ex:Server3 .
ex:David ex:accesses ex:Server1 .

ex:SoftwareA ex:hasVulnerability "CVE-2023-1234" .
ex:SoftwareB ex:hasVulnerability "CVE-2023-9999" .

ex:Alice ex:name "Alice" .
ex:Bob ex:name "Bob" .
ex:Charlie ex:name "Charlie" .
ex:David ex:name "David" .
EOF

    cat << 'EOF' > /home/user/bad_query.sh
#!/bin/bash
VULN_ID=${1:-"CVE-2023-1234"}

# The missing link is that ?emp accesses ?someServer, but ?someServer is never linked to ?server.
QUERY="
PREFIX ex: <http://example.org/>
SELECT ?employeeName ?server
WHERE {
  ?server ex:runs ?software .
  ?software ex:hasVulnerability \"${VULN_ID}\" .
  ?emp ex:name ?employeeName .
  ?emp ex:accesses ?someServer .
}
"

roqet -q -r json -e "${QUERY}" /home/user/infra.ttl
EOF
    chmod +x /home/user/bad_query.sh

    chmod -R 777 /home/user
