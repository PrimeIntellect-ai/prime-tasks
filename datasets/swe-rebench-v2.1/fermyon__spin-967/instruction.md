Add `spin up` option to mount static asset directory directly
Currently, `spin up` always copies static assets into a temporary directory and mounts that into the host.  This creates friction when iteratively developing static assets (e.g. SPAs) since `spin up` must be restarted each time any asset changes in order for the updated asset to be served.

I'm proposing that we add an option, e.g. `--direct-mount` to mount the asset directory directly instead of using a temporary directory, so that changes on the host filesystem are immediately visible to subsequent app invocations, with no restart required.

### Additional contract requirements

- The public loader entry point `spin_loader::local::from_file` (in `crates/loader/src/local/mod.rs`) accepts an optional base destination directory: `from_file(app: impl AsRef<Path>, base_dst: Option<impl AsRef<Path>>, bindle_connection: &Option<BindleConnectionInfo>) -> Result<Application>`.
- When `base_dst` is `Some(dir)`, local assets are copied into a temporary directory under `dir`, and that copy is mounted.
- When `base_dst` is `None`, the asset directories declared in the manifest are mounted directly from their source location, so that changes made to those directories on the host filesystem are visible to subsequent app invocations without a restart.
