Should 'Too many recipients' return 452 4.5.3 instead of 552 5.5.3?
I've been looking into this response a bit for something I'm working on. The current response when we have a recipient limit is

```
552 5.5.3 Maximum limit of %v recipients reached
```

From my reading though, it seems the following is the more 'standard' response for this case

```
452 4.5.3 Too many recipients
```

with some providers including the limit there. Specifically I'm concerned with how the big players say to handle this status code to make sure that they send correctly with fewer recipients. I'm about to do testing with the current code and will report my findings, but I think this should be changed.

**Gmail**: [https://support.google.com/a/answer/3726730](https://support.google.com/a/answer/3726730)
> 452, "4.5.3", Your message has too many recipients. For more information regarding Google's sending limits, visit [Limits for sending & getting mail.](https://support.google.com/mail/answer/22839)

**Microsoft**: [https://support.google.com/a/answer/3726730](https://support.google.com/a/answer/3726730)
> For inbound email, the Receive connector MaxRecipientsPerMessage is verified first. However, if the number of recipients exceeds the limit, the message is not rejected; the connection receives the error, 452 4.5.3 Too many recipients. Most mail servers understand this error and they will continue to resend the message in another connection until the message is delivered to all recipients.

Granted they are talking about their own servers and how they expect clients to handle it, so I would hope they respond the same way. The rfc's may suggest that 5xx is more correct (I don't think they specifically say what to do for too many recipients), but if gmail and ms agree on something else, I would consider it the de-facto standard.
