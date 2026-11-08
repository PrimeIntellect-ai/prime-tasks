#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > router.sh
#!/bin/bash
URI="$1"
PATH_PART="${URI%%\?*}"
QUERY_STRING="${URI#*\?}"

if [ "$PATH_PART" = "/api/migrate" ]; then
    # BROKEN PR CODE: only works if 'target' is the first parameter
    TARGET=$(echo "$QUERY_STRING" | cut -d'&' -f1 | cut -d'=' -f2)

    if [[ ! "$QUERY_STRING" =~ "target=" ]]; then
        echo "Error: target missing"
        exit 1
    fi

    if [ ! -f "fixtures/schema_v1.json" ]; then
        echo "Error: Base fixture missing"
        exit 1
    fi

    echo "Migrating to schema $TARGET"
else
    echo "404 Not Found"
fi
EOF
    chmod +x router.sh

    cat << 'EOF' > test.sh
#!/bin/bash

for i in {1..50}; do
    TARGET=$RANDOM
    PREFIX_PARAM="dummy=$RANDOM"
    SUFFIX_PARAM="foo=bar"

    ORDER=$((RANDOM % 3))
    if [ $ORDER -eq 0 ]; then
        QUERY="target=${TARGET}&${PREFIX_PARAM}&${SUFFIX_PARAM}"
    elif [ $ORDER -eq 1 ]; then
        QUERY="${PREFIX_PARAM}&target=${TARGET}&${SUFFIX_PARAM}"
    else
        QUERY="${PREFIX_PARAM}&${SUFFIX_PARAM}&target=${TARGET}"
    fi

    OUTPUT=$(./router.sh "/api/migrate?$QUERY")
    if [[ "$OUTPUT" != "Migrating to schema $TARGET" ]]; then
        echo "Test failed for query: $QUERY"
        echo "Got: $OUTPUT"
        exit 1
    fi
done
echo "All tests passed."
EOF
    chmod +x test.sh

    chown -R user:user /home/user/app
    chmod -R 777 /home/user
