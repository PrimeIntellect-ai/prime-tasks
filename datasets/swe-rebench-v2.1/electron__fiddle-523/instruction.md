Gist description dialog box should have a cancel button
0.17.1

![image](https://user-images.githubusercontent.com/172800/97211663-95b54300-177c-11eb-835b-a6eb5509a697.png)

I'd like to be able to go back to my editors and update something before filling this in!

### Additional contract requirements

- The description dialog is a generic dialog configured with a cancel button: the generic dialog options' `cancel` field is set to a non-empty label.
- `getFiddleDescriptionFromUser` returns the entered description text when the user confirms the dialog, and `null` when the user cancels it.
