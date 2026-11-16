Add some way to remove a closed process
I'm attaching to specific individual processes and want to know when they are closed, so I use
```rust
if system.refresh_processes_specifics(ProcessesToUpdate::Some(&[pid]), ProcessRefreshKind::new()) == 0 {
    ...
}
```
to check for that situation. Unfortunately as stated by the documentation, this does not remove it from the entire list of processes. This means I need to run
```rust
system.refresh_processes_specifics(
    ProcessesToUpdate::All,
    ProcessRefreshKind::new().with_exe(UpdateKind::OnlyIfNotSet),
);
```
inside to ensure it gets removed. This is very wasteful. I'd appreciate some sort of way for me to either manually remove it from the list or some argument I can pass / config I can set, so it gets removed properly.

Though arguably the entire default seems questionable to me too.

### Additional contract requirements

- Add a public method `System::refresh_processes(&mut self, processes_to_update: ProcessesToUpdate<'_>, remove_dead_processes: bool) -> usize` in the `sysinfo` crate. It refreshes the selected processes and returns the number of updated processes. When `remove_dead_processes` is `true`, any refreshed process that is detected as dead is removed from the system process list; when it is `false`, dead processes remain in the list.
- Add a public method `System::refresh_processes_specifics(&mut self, processes_to_update: ProcessesToUpdate<'_>, remove_dead_processes: bool, refresh_kind: ProcessRefreshKind) -> usize` in the `sysinfo` crate. It performs a fine-grained refresh of the selected processes and returns the number of updated processes. When `remove_dead_processes` is `true`, any refreshed process that is detected as dead is removed from the system process list; when it is `false`, dead processes remain in the list.
