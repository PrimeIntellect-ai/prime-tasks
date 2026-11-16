bug: the input reader gobbles up characters after escape sequences
When a composite input is inserted in the terminal, the terminal can deliver many bytes at once to the process, including escape sequences interleaved with regular keypresses. (This also happens after a process is resumed from sleep and there were input queued while the process was sleeping.)

Currently the input reader only recognizes input boundaries when the read call returns (i.e. no more input to be read).
It is also unable to recognize when an escape sequence is followed by regular bytes (it fails to detect the sequence in the special control character map).

[HIDDEN]

This is partly addressed by #397 but it should really be fixed independently of the bracketed paste feature, as it would benefit any composite input.

### Additional contract requirements

- When the reader receives 1000 consecutive printable `a` characters, it must emit a single `KeyMsg` whose `Runes` contains all 1000 characters.
- When composite input contains an escape sequence followed by ordinary keypress bytes, the reader must emit the sequence's message and continue parsing the remaining bytes without swallowing them.
