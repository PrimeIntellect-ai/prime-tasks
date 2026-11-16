Multiple reply_to addresses (Sendgrid)
**Is your feature request related to a problem? Please describe.**
There should be a way to specify multiple addresses for `reply_to`.

**Is your feature request related to a specific adapter? Please specify.**
Sendgrid

Now there is a way to add multiple addresses in `reply_to` (at least in sendgrid) - https://docs.sendgrid.com/api-reference/mail-send/mail-send#multiple-reply-to-emails

I am thinking about preparing a PR but looks like it will affect `Email` type (which has `reply_to: mailbox() | nil`) so I am thinking how to do it and to not break everything else. Do you think it makes sense to change type to `[mailbox()] | []` and handle it everywhere?

### Additional contract requirements

- When delivering multiple reply-to addresses through SendGrid, use SendGrid’s documented `reply_to_list` request field.
