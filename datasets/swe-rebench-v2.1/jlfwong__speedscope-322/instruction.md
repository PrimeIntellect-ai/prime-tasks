Incorrect scoping for chrome tracing format file
When importing from a chrome tracing format file I see some problems with scoping.

![speedscope](https://user-images.githubusercontent.com/8567076/60436645-616f5800-9c04-11e9-8214-97205b801070.PNG)

The difference between good.json and bad.json is just the order of events in the file. good.json has the events in ascending timestamp order, bad.json has two events out of order. The trace event format specification says that "The events do not have to be in timestamp-sorted order." so this shouldn't matter. Both display fine in chrome://tracing.

[good.json.txt](https://github.com/jlfwong/speedscope/files/3345555/good.json.txt)
[bad.json.txt](https://github.com/jlfwong/speedscope/files/3345558/bad.json.txt)

The original data is from LLVM -ftime-trace with some additional processing afterwards.


Trace event profiles containing multiple 'X' events w/ identical ts & dur fail to import
I'm using speedscope to analyze clang's `-ftime-trace`. However speedscope is unable to analyze some of my .json files (possibly due to updating to Clang 11).

"😿 Something went wrong. Check the JS console for more details."

```
Failed to load format Error: Tried to leave frame "DebugType {"detail":"std::_Locinfo"}" while frame "DebugType {"detail":"const std::_Locinfo"}" was at the top at 3403256
    _leaveFrame https://www.speedscope.app/speedscope.a3aeba39.js:168
    leaveFrame https://www.speedscope.app/speedscope.a3aeba39.js:168
    o https://www.speedscope.app/import.1c646c77.js:111
    p https://www.speedscope.app/import.1c646c77.js:111
    S https://www.speedscope.app/import.1c646c77.js:113
    s https://www.speedscope.app/import.1c646c77.js:113
```

or similar errors. I uploaded two files, one of which breaks speedscope:

[speedscope-json.zip](https://github.com/jlfwong/speedscope/files/5416452/speedscope-json.zip)

- output.cpp.json works.
- sample_docs.cpp.json throws an error, but with a much longer stack trace.

This seems similar but not identical to https://github.com/jlfwong/speedscope/issues/299.

```
C:\Users\nyanpasu>clang --version
clang version 11.0.0
Target: x86_64-pc-windows-msvc
Thread model: posix
InstalledDir: C:\Program Files\LLVM\bin
```

### Additional contract requirements

- When complete (`X`) events overlap without nesting, represent the crossing intervals with stack segments `alpha 5.00µs` and `alpha;beta 10.00µs` for events `alpha` at timestamp 0 with duration 10 and `beta` at timestamp 5 with duration 10.
- When two complete (`X`) events have the same start timestamp and the same duration, the event listed first in the file is the outer frame and the event listed second is nested inside it.
