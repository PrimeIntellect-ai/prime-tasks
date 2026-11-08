download command doesn't support filters with HasAttachment
When running the `download` subcommand, it fails with

```
$ gmailctl download
error importing filter #0: empty criteria
```

In looking at it, my first filter is one that labels things with File Attachments:

<img width="421" alt="image" src="https://user-images.githubusercontent.com/4735/78503014-ad1dd780-7729-11ea-95ce-73137c47dba1.png">

As that has no criteria around those defaulted or assumed filters, it fails, even though it's something you can create a filter around.

It would be nice to be able to have it skip over these if they aren't currently downloadable, or to add support for other criteria fields.
