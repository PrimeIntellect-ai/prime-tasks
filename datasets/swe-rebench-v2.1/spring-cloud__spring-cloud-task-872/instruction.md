Mariadb needs to be treated as a independent db type.
Currently Task treats mariadb as a version of MySql.   Task needs to treat mariadb as its own type.

### Additional contract requirements

- Expose the distinct MariaDB database type as `DatabaseType.MARIADB`.
