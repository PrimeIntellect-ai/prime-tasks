Using Since in imap filter turn into error with Seznam.cz provider
**Environment**
- **PHP version:8.3.4**
- **ImapEngine version:1.10.1**
- **IMAP server:Seznam.cz**

**IMAP logs**
DirectoryTree\ImapEngine\Exceptions\ImapCommandException
IMAP command "TAG4 UID SEARCH SINCE "04-Apr-2025"" failed. Response: "TAG4 NO SEARCH: mtd: internal error: Bad token (expecting date specification) ."

Same problem was already mentioned in different project https://github.com/freescout-help-desk/freescout/issues/4182

[HIDDEN]

### Additional contract requirements

- A SINCE criterion must be sent as an IMAP date specification without surrounding quotes, so the server can process it.
