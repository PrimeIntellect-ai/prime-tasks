Way to switch intents?
Is there a way to trigger/switch an intent manually?

My use case:
An intent is triggered.
Logic is performed that decides if a user has access to this particular intent.
If not, then pass the user to another intent on the alexa service and continue the interaction.

### Additional contract requirements

From an intent handler, `request.getRouter().intent(name)` hands the current interaction to the registered intent named `name`. The destination handler runs for that interaction, and its response is delivered to the user.
