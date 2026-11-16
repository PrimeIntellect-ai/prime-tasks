Send email to handler on application submit

### Additional contract requirements

- The translation of an event and its application into emails is performed by the function `event-to-emails-impl` in the namespace `rems.poller.email` (source file `src/clj/rems/poller/email.clj`). It takes an event map and an application map and returns a vector of email maps.
- For an event of type `:application.event/submitted`, one email is produced for every handler listed in `[:application/workflow :workflow.dynamic/handlers]` of the application.
- Each such submission email uses `:to-user` as its recipient key, has the exact subject `A new application has been submitted`, and has the body `Dear <handler>,\nUser <applicant> has submitted a new application <application-number>.\nView the application: <application-link>`, where `<handler>` is the handler, `<applicant>` is the application's applicant, `<application-number>` is the application's external id (falling back to its id when no external id is set), and `<application-link>` is the public URL of the application.
- Every returned email map contains at least the keys `:to-user` (or `:to`), `:subject`, and `:body`.
