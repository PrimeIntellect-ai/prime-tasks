Mail.put_text can delete plain text attachments
Currently [`Mail.put_text/2`](https://github.com/DockYard/elixir-mail/blob/master/lib/mail.ex#L38) tries to replace a plain text part, but [doesn't differentiate](https://github.com/DockYard/elixir-mail/blob/master/lib/mail.ex#L40) between normal message parts and attachments.
<!-- BUG TEMPLATE -->
## Version
0.2.1
## Steps to reproduce
in the following snippet the first attachment will be replaced with the text from the `put_text`-statement.
```elixir
Mail.build_multipart()
|> Mail.put_attachment({"Attachment.txt", "I am the first attachment"})
|> Mail.put_attachment({"Attachment2.txt", "I am the second attachment"})
|> Mail.put_text("I am the message body")
```
## Expected Behavior
Both attachments remain untouched and the text from the `put_text`-statement is added.
## Actual Behavior
The first attachment is replaced with the text from the `put_text`-statement.
