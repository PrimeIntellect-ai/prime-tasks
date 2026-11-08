Allow unknown properties in connection URL / properties
Some applications automatically add additional properties to the Connection URL or Connection properties. Properties that are unknown to the Spanner JDBC driver will cause the driver to throw an error. This prevents the driver to be used with some applications, such as for example the IntelliJ Database Navigator: https://stackoverflow.com/questions/64975569/connecting-to-a-gcloud-spanner-emulator-instance-from-intellijs-database-naviga

The driver should therefore also have a mode where unknown properties do not cause errors but only warnings.

### Additional contract requirements

- The warning-only mode is enabled by setting the connection property `lenient=true`, supplied either in the connection URL or in the JDBC connection `Properties`.
- When `lenient=true`, unknown properties supplied either in the connection URL or in the JDBC connection `Properties` must not cause an error. The connection is returned successfully and a warning is available through `java.sql.Connection#getWarnings()`; the warning message contains the name of the unknown property.
- When `lenient=true` is not set, an unknown property causes a `java.sql.SQLException` whose message contains the name of the unknown property.
