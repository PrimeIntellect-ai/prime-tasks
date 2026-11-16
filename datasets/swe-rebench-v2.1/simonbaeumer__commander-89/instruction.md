Running `commander add --file tests/commander.yaml my-command` removes test validation from commander.yaml
### Prerequisites

* [x] Can you reproduce the problem?
* [x] Are you running the latest version?
* [x] Did you perform a cursory search?

### Description

When using the automatic adding of tests, manually added tests validation is removed.

### Steps to Reproduce

1. run `commander add --file tests/commander.yaml ./setup-update-tag.sh`
2. check what has changed in the file (e.g. `diff --git a/tests/commander.yaml b/tests/commander.yaml`)

**Expected behavior:** `commander add` should just add new tests, not modify existing ones (resorting the file may be fine)

**Actual behavior:** It restructures the file and drops test cases. Basically removing most manually made edits.

```
diff --git a/tests/commander.yaml b/tests/commander.yaml
index 3156fb7..15b5d6c 100755
--- a/tests/commander.yaml
+++ b/tests/commander.yaml
@@ -1,33 +1,18 @@
 tests:
-  setup with existing .env:
-    command: ./setup.sh
+  ./setup-update-tag.sh:
     exit-code: 1
-    stdout: |-
-      Creating individual env files for containers (if they do not exist already)
-      .env already exists with initial configuration
-      If you want to change the configuration, please edit .env directly
+    stdout: Please install reg in order to run this script.
   ./version.sh:
     exit-code: 0
   ./version.sh core:
     exit-code: 0
-    stdout:
-      not-contains:
-        - core-
-        - Debian
-        - amd64
-        - tar.gz
   ./version.sh webapp:
     exit-code: 0
-    stdout:
-      not-contains:
-        - webapp-
-        - Debian
-        - amd64
-        - tar.gz
   ./version.sh zpush:
     exit-code: 0
-    stdout:
-      not-contains:
-        - Debian
-        - amd64
-        - tar.gz
+  setup with existing .env:
+    exit-code: 1
+    stdout: |-
+      Creating individual env files for containers (if they do not exist already)
+      .env already exists with initial configuration
+      If you want to change the configuration, please edit .env directly
```

### Specifications

 - Version: 1.12.0
 - Platform: Ubuntu 16.04
 - Subsystem:

You can get the version information from executing `commander --version`.

### Additional contract requirements

- When adding `echo hello` to a suite containing `exists`, the serialized YAML must place the `echo hello` entry before `exists`.
