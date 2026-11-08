send_with_template won't allow alias
Referring to #150

When I try to send an email using a template alias,
`postmark.emails.send_with_template(TemplateAlias=alias, TemplateModel=model, To=sendto, From=efrom)`

I get the following response:
`TypeError: send_with_template() missing 1 required positional argument: 'TemplateId'`

Thanks.
