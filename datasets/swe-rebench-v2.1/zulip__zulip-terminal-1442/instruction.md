Improve handling of pressing `Esc` during message compose
Currently `Esc` can be pressed to exit compose, without sending the message.

This can be useful if one wants to cancel the send, but can also be frustrating if accidentally hitting the key after having written a good message which you intend to send.

This can be made worse, if a key is near the `Esc` key and used for composition, eg. the <kbd>`</kbd> key for inline code or quote/code blocks.

Ideas for resolving this:
- Prompt with a confirmation popup to exit compose, if there is more than some threshold of content present (could be empty message, could be 5, 10, 15, ... characters)
- Prompt with a variation on a confirmation popup, giving the option to save as a draft
- Automatically save as a draft, but prompt if a draft already exists (like we do now)
- Automatically save as a draft - *only possible if we support more than one draft in the session, ie. improve draft handling generally ~ #302)

Please discuss this in the stream before proceeding with this, since it would be good to get more views on this first.

### Additional contract requirements

When Esc is pressed while composing a message whose unsent body contains at least 15 characters, the compose view must not be left immediately: display a confirmation popup asking the user to confirm leaving. A shorter message may also receive this protection. Confirming must leave composition without sending the message; declining must dismiss the prompt and return to the compose view with the message intact.
