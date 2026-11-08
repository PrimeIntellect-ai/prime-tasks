Trigger is encoded twice
Because the input is already encoded from the [HIDDEN].
This leads to \n inside the value of the trigger

https://github.com/adamgibbons/ics/blob/ecc8cf54f84da92b3a0fe0fa049fc65cda4d1451/src/utils/set-alarm.js#L58C26-L58C26

### Additional contract requirements

- An emitted alarm's trigger value must not contain an extra literal `\n` sequence introduced by encoding.
