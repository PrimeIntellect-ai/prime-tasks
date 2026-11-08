Proper board mode header labels & icons
Currently the board access mode is displayed above the board title and is somewhat misleading with the labels "Private board" and "Public board". Also the icons should be reworked as a lock is displayed right next to "Public board".

In the future the label should be changed to ...

- "Open board" and a fitting icon (e.g. a globe), which means that a board might be entered by the URL
- "Password protected" and a fitting icon
- "Closed board" and a fitting icon, which means that the admins will verify join attempts

If you have better ideas you can also change this suggestion.

### Additional contract requirements

- Use the translation keys `AccessPolicy.PUBLIC`, `AccessPolicy.BY_PASSPHRASE` and `AccessPolicy.BY_INVITE` for the Open, Password protected and Closed access modes, respectively.
