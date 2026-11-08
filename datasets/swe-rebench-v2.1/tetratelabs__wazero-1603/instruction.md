Plan9 compilation support
I am attempting to compile a program using Wazero to Plan9, since Go's compiler supports the target, however, pretty much everything related to Errno and Syscalls are broken, filled with Undefineds.
If it would be possible, I would like to have a mode where it can successfully compile to GOOS=plan9.
I am not adverse to implementing this change myself in a PR, however, I have no idea if this would be possible or not, nor where to start. I understand my use case is niche, but if I could get this working, it would potentially allow programs compiled to WASM to run on another OS, and I would be grateful.
