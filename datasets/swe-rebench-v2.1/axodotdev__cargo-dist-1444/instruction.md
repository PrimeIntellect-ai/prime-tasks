shell: Standalone updater installation has broken
A recent change has broken the installation of standalone updaters via the shell installers. The PowerShell installers appear to be unaffected. On affected versions of cargo-dist, the shell installer information will be updated looking like this:

```sh
_updater_name=""
_updater_bin=""
```

Instead of specifying the actual name and binary. This was probably introduced in a recent refactor in 19af85324be25d023b2bac291aa105f081d7da30, [HIDDEN] The PowerShell installer still uses the other kind of artifact, so it's unaffected.
