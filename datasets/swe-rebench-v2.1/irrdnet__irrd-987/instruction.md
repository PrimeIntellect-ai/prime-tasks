Debian/Ubuntu whois client sending -V flag
**Describe the bug**
The whois client from Debian/Ubuntu has our server (rr.ntt.net) in an array of "RIPE-like servers" which causes it to prepend `-V <user-agent>` to queries. When combined with `!` commands, this results in the server responding with `%  No entries found for the selected source(s).`

**To Reproduce**
Using the whois client from Debian / Ubuntu ([Github](https://github.com/rfc1036/whois)):

```
whois -h rr.ntt.net '!s-lc'
whois -h rr.ntt.net '!v'
```

This client is also available in Homebrew for Mac (`brew install whois`)

The hostname (assuming it's in the `ripe_servers` array) must be used to trigger the problem. `-h <ip-address>` does not send `-V` and in that case queries work properly.

**Expected behaviour**
Return the requested data, e.g.

```
❯ whois -h rr.ntt.net '!v'
A22
IRRd -- version 4.4.4
C

❯ whois -h rr.ntt.net '!s-lc'
A127
NTTCOM,INTERNAL,LACNIC,RADB,RIPE,RIPE-NONAUTH,ALTDB,BELL,LEVEL3,APNIC,JPIRR,ARIN,BBOI,TC,AFRINIC,IDNIC,RPKI,REGISTROBR,CANARIE
C
```

**IRRd version you are running**
4.4.4

**Additional context**
This is an issue with the client doing the wrong thing. However, even if we fix the client, it is shipped with Debian/Ubuntu Linux and will take a very long time to filter out to the world. So it may be better to handle this case in the server, knowing the incorrect client behavior exists.

### Additional contract requirements

When a `-V <user-agent>` prefix precedes an IRRd `!` command, the server must process that command and return its requested data rather than report that no entries were found. This applies to IRRd commands generally, not only the `!v` and `!s-lc` examples above.
