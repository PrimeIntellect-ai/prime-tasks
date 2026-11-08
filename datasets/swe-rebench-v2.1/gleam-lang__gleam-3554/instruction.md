Missing empty line between last warning and first error
When there's both warnings and errors in a Gleam project the last warning and the first error are printed with no empty line separating them
![Screenshot 2024-08-19 alle 18 28 23](https://github.com/user-attachments/assets/d2d340d5-2c80-40cc-9161-607415cd8fbc)

### Additional contract requirements

- When a project produces both warnings and errors, leave an empty line between the final warning and the first error.
- In warning output, print the diagnostic immediately after the `//// Warning` heading, with no empty line between them, including for `warning: Unused private constructor` and `warning: Unused private type`.
