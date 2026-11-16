Add placeholder text in user entry fields
**Is your feature request related to a problem? Please describe.**
Not a problem

**Describe the solution you'd like**
To be able to add placeholder text such as "Enter your text here..." that disappears when a user clicks into the field.

**Describe alternatives you've considered**
Having normal text in the field that needs to be deleted (requires users to delete it and breaks immersion)
Having text that can remain and be ignored via code (such as: ">> ")

**Additional context**
PyQT5 has this functionality

### Additional contract requirements

A caller must be able to provide a chosen placeholder string for a `UITextEntryLine` using the optional `placeholder_text` constructor keyword. The placeholder is shown while the field is empty and unfocused, hidden while it is focused or contains text, and shown again when it becomes empty and unfocused.
