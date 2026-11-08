Command for cleanup of installed standalone python versions
**How would this feature be useful?**

<!-- Describe any use cases this solves or frustrations it alleviates.   -->
#1242 introduced the ability to have pipx download standalone python versions, if the requested python version is not available. Currently, there is no way through pipx to delete them again. Having a way for pipx to figure out which interpreters are still in use and delete the ones that aren't would be very useful for housekeeping.

Also see the discussions in the merge review of the feature for more information: https://github.com/pypa/pipx/pull/1243#issuecomment-1932170921

**Describe the solution you'd like**

<!-- If you have an idea of how to do this, write it here! -->
A new command that checks the interpreters of the installed applications, compares it with the available standalone python versions and deletes the versions that are no longer in use.

**Describe alternatives you've considered**

<!-- If there's some workaround or alternative solutions, let us know. -->
Manually going to the `PIPX_STANDALONE_PYTHON_CACHEDIR` folder and removing python versions, hoping they are not used anymore.

### Additional contract requirements

- Expose the cleanup operation as `pipx interpreter prune`, and provide a `pipx interpreter list` command that lists cached standalone Python interpreters and identifies whether each is used by installed applications. Its output must include `Standalone interpreters`; when there are no standalone interpreters, this must be the only output line. For each listed version, output `Python <version>` and identify users by application package name, or output `Unused` if it has no users. When pruning finds no unused interpreters, print `Nothing to remove`; when it removes interpreters, print `Successfully removed:` followed by a line `- Python <version>` for each removed version.
