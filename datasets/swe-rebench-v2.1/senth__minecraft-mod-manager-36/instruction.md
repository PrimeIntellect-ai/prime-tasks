Mod is already installed - Can't reinstall mod after manually deleting it
When you install a mod via the mod manager and then delete it from the folder and try to install it again via the manager it says the mod is already installed.

I had thinked about an uninstall command line to delete the mod from the database as a possible solution.

### Additional contract requirements

- Reinstalling a mod that was previously installed and then manually deleted from the mods folder must succeed: the manager must not report it as already installed, the database write performed while reinstalling must not fail because an inactive row for the same mod id still exists, and afterward the mod must be treated as installed again.
