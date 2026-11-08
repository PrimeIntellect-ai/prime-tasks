Export should allow the export of methods that do not end in dbus.Error
One may wish to be able to export objects from packages that do not import the 'dbus' library, and whose methods do not use the dbus.Error return type. When exporting these functions, a wrapper can be generated that will return dbus.Error for them for D-Bus specific failures, and will encapsulate the existing 'error' return if it exists and is the last return from a method. If an 'error' is not returned then the wrapper should only encapsulate D-Bus specific failures.

There is some risk in doing this as it would be a subtle API change that could cause unintended methods to be exported if one is using dbus.Error as a flag that this method should be exported on D-Bus. My suggestion would be to have an 'ExportAll' variant for exporting all methods from an object that are exported to packages.

If no one has any objections I will get this implemented.

### Additional contract requirements

Add a public method `Conn.ExportAll(v interface{}, path ObjectPath, iface string) error` in package `dbus`. It registers all exported methods defined by `v` under the interface `iface` at the object path `path`, and returns nil on success.

Any exported method may be exported regardless of its signature. When a method's first parameter is of type `Message`, it receives the incoming raw `Message`. A method may return a standard Go `error` as its last return value, or no error at all.
