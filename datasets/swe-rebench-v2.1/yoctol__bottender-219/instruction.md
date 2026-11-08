LINE -  Alias ButtonsTemplate to ButtonTemplate
Its name should be `Buttons template`
https://developers.line.me/en/docs/messaging-api/reference/#buttons

### Additional contract requirements

- Expose a ButtonsTemplate-named counterpart for each ButtonTemplate reply, push, and send operation on the LINE context. The singular ButtonTemplate names must remain available, and each plural-name operation must provide the same observable behavior as its singular counterpart. In particular, `LineContext.sendButtonsTemplate(altText, template)` must accept the same arguments and behave like `sendButtonTemplate`.
