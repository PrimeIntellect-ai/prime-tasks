MIDI note on/off processing is incomplete
MIDI has two ways to represent a note-off: as a note-off command, or as a note-on command with velocity zero.

1. Very often, you do not want to trigger on note-ons if they have velocity zero.
2. Less often, you want to remap "note off" commands to "note on with velocity zero" commands.

The code handles 2.  We should handle 1.

Added this as a 4.0 issue because it's a gross bug if you use MIDI notes, and the fix is tiny.
