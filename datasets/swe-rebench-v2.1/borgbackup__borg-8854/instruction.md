borg2: cache not removed after archive deletion & compaction
In borg2 beta16, the local cache file corresponding to an archive series is not being removed after all archives from that series are deleted, even when the `borg compact` operation is executed. This leads to unnecessary cache files lingering in the system which should be cleaned up as part of the compaction process.

Steps to Reproduce:

- Create a repository and add multiple archives in a specific series.
- Delete all archives in that series using the `borg delete` command.
- Run `borg compact` to compact the repository and reclaim space.
- Observe that the corresponding cache file for the deleted archive series is not removed.

### Additional contract requirements

- When `borg compact` performs files-cache cleanup, its output must contain the exact phrase `Cleaning up files cache`.
