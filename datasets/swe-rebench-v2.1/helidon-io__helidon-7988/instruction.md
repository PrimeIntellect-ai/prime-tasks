Upgrade to mysql-connector-j 8.2.0 or newer
Upgrade to mysql-connector-j 8.2.0 or newer. Need to do this in:

- [x] 2.x
- [x] 3.x
- [x] 4.x #7988

### Additional contract requirements

- The MySQL JDBC driver `com.mysql:mysql-connector-j` must be managed by this repository's dependency management at version 8.2.0 or newer, so that projects depending on the managed version pick up that driver release.
