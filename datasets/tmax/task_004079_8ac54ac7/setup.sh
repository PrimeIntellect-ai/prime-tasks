#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev patch
    pip3 install pytest

    mkdir -p /home/user/src /home/user/data /home/user/bin /home/user/output

    cat << 'EOF' > /home/user/src/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("fopen");
        return 1;
    }

    int id;
    int ts;
    char action[256];
    int count = 0;

    while (fscanf(f, "%d\t%d\t%255s", &id, &ts, action) == 3) {
        count++;
    }
    fclose(f);

    printf("Processed %d legacy records.\n", count);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/update.patch
--- processor.c	2023-10-25 10:00:00.000000000 +0000
+++ processor_new.c	2023-10-25 10:05:00.000000000 +0000
@@ -14,17 +14,24 @@
         return 1;
     }

-    int id;
-    int ts;
+    char uid[256];
+    char event_time[256];
     char action[256];
     int count = 0;
+    int logins = 0;

-    while (fscanf(f, "%d\t%d\t%255s", &id, &ts, action) == 3) {
+    while (fscanf(f, "%255[^\t]\t%255[^\t]\t%255s\n", uid, event_time, action) == 3) {
         count++;
+        if (strcmp(action, "login") == 0) logins++;
     }
     fclose(f);

-    printf("Processed %d legacy records.\n", count);
+#ifdef MINIMAL_CONTAINER
+    printf("MINIMAL_STAT: %d total, %d logins\n", count, logins);
+#else
+    printf("Processed %d records. Total logins: %d\n", count, logins);
+#endif
+
     return 0;
 }
EOF

    cat << 'EOF' > /home/user/data/old_events.tsv
101	1682856000	login
102	1682856060	logout
103	1682856120	login
101	1682856180	view
104	1682856240	login
105	1682856300	purchase
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
