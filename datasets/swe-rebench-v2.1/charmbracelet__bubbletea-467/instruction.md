Unknown CSI inputs result in garbage key events
When a terminal CSI sequence is not recognized by bubbletea, it is not completely ignored; instead, bubbletea will match the initial escape byte and the character immediately afterwards as a single key with the alt modifier, then interpret the rest as regular key inputs. For example, ESC [ 1003 h  gets parsed as alt+1, then 0, then 0, then 3, then h.

Since the CSI sequences all have a regular structure, they could be parsed and ignored as a single unit.

(The definition is strict: a CSI sequence starts with `ESC [` and terminates with a byte value in the range 0x40 to 0x7E.)
