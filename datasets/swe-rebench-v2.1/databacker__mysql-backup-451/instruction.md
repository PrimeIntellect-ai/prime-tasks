Add support for DB_PASS_FILE to enable Docker Swarm secrets
**Current Behavior**

mysql-backup uses environment variables DB_PASS, but lacks support for the _FILE suffix used for secure credential handling in containerized environments like Docker Swarm.

**Expected Behavior**

The mysql-backup should support DB_PASS_FILE to securely read passwords from files, aligning with best practices for Docker Swarm secrets.

**Use Case**

Docker Swarm stores secrets as files (/run/secrets/), but mysql-backup requires passwords as environment variables, increasing exposure risk. Supporting _FILE enables secure secret management.

### Additional contract requirements

- The `DB_PASS_FILE` environment variable names a file from which the database password is read.
- The CLI must accept a `--pass-file` flag to read the database password from the specified file.
- When both `--pass` and `--pass-file` are set, `--pass` takes precedence.
- When both `DB_PASS` and `DB_PASS_FILE` are set, `DB_PASS` takes precedence.
