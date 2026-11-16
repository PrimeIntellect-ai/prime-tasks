Wrong Content-Type for some JSON responses like 404's
<!--
All bug reports must provide the following background information
Text between <!-- and --​> marks will be invisible in the report.

IF YOUR ISSUE IS CONSIDERED A SECURITY VULNERABILITY THEN PLEASE STOP
AND DO NOT POST IT AS A GITHUB ISSUE! Please report the issue responsibly by
disclosing in private by email to security@matrix.org instead. For more details, please
see: https://www.matrix.org/security-disclosure-policy/
-->
#### Reported-By: @roughnecks
### Background information
<!-- Please include versions of all software when known e.g database versions, docker versions, client versions -->
- **dendrite.matrix.org**
- **Dendrite version or git SHA**: 0.13.6+87f028d
- **Client used (if applicable)**: Element Web >= 1.11.60

### Description

- **What** is the problem: Dendrite returns the wrong content type for 404 M_UNKNOWN, text/plain, for example for `/_matrix/client/unstable/org.matrix.msc2965/auth_issuer`
- **Who** is affected: People using Dendrite with Element Web, or anyone else requiring json as the content type
- **How** is this bug manifesting: Element tells you "your Element is misconfigured"
- **When** did this first appear: Element Web 1.11.60, i suspect the return type hasn't been important before though

<!--
Examples of good descriptions:
- What: "I cannot log in, getting HTTP 500 responses"
- Who: "Clients on my server"
- How: "Errors in the logs saying 500 internal server error"
- When: "After upgrading to 0.3.0"

- What: "Dendrite ran out of memory"
- Who: "Server admin"
- How: "Lots of logs about device change updates"
- When: "After my server joined Matrix HQ"

Examples of bad descriptions:
- What: "Can't send messages"  - This is bad because it isn't specfic enough. Which endpoint isn't working and what is the response code? Does the message send but encryption fail?
- Who: "Me" - Who are you? Running the server or a user on a Dendrite server?
- How: "Can't send messages" - Same as "What".
- When: "1 day ago" - It's impossible to know what changed 1 day ago without further input.
-->

### Steps to reproduce
<!-- Please try reproducing this bug before submitting it. Issues which cannot be reproduced risk being closed. -->

- go to app.element.io
- set server to dendrite.matrix.org
- observe the error

<!--
Describe how what happens differs from what you expected.

If you can identify any relevant log snippets from server logs, please include
those (please be careful to remove any personal or private data). Please surround them with
``` (three backticks, on a line on their own), so that they are formatted legibly.

Alternatively, please send logs to @kegan:matrix.org, @s7evink:matrix.org or @devonh:one.ems.host
with a link to the respective Github issue, thanks!
-->

### Headers
```bash
curl https://dendrite.matrix.org/_matrix/client/unstable/org.matrix.msc2965/auth_issuer -I
HTTP/2 404
date: Sun, 07 Apr 2024 14:16:16 GMT
content-type: text/plain; charset=utf-8
content-length: 59
access-control-allow-headers: Origin, X-Requested-With, Content-Type, Accept, Authorization
access-control-allow-methods: GET, POST, PUT, DELETE, OPTIONS
access-control-allow-origin: *
strict-transport-security: max-age=15724800; includeSubDomains
cf-cache-status: DYNAMIC
server: cloudflare
cf-ray: 870aa26e0a396661-AMS
```

### Explanation
> the content is fine, but the <code>Content-Type</code> header must be <code>application/json</code> as per the spec: https://spec.matrix.org/v1.10/client-server-api/#api-standards<blockquote>Servers must include a Content-Type header of application/json for all JSON responses.</blockquote>

\- Michael (t3chguy) => https://matrix.to/#/!YTvKGNlinIzlkMTVRl:matrix.org/$Ccl7mmAOGI8KhBJ0BzOM63Wje1gcmh2IX6tAchUXXZ8?via=matrix.org&via=privacytools.io&via=mozilla.org
