SMTP2GO: Reply-To field is ignored
Setting a reply-to field with reply_to/2 does not do anything. In fact, looks like the SMTP2GO adapter just doesn't process that field at all.

### Additional contract requirements

- When an email also has custom headers, the SMTP2GO request's `custom_headers` list must place the `Reply-To` entry before those custom-header entries.
- - When `reply_to/2` supplies multiple addresses, the SMTP2GO request's `custom_headers` list must contain a `Reply-To` entry whose value joins the addresses with `, `, as in `reply-to1@example.com, reply-to2@example.com`.
