parseVersion1() is not secure
```
func parseVersion1(reader *bufio.Reader) (*Header, error) {
	// Read until LF shows up, otherwise fail.
	// At this point, can't be sure CR precedes LF which will be validated next.
	line, err := reader.ReadString('\n')
```

The `reader` is a default `bufio.Reader` wrapping a `net.Conn`. It will read from the connection until it finds a newline. Since no limits are implemented in the code, a deliberately malformed V1 header could be used to exhaust memory in a server process using this code - a form of DDoS. The exploit is simple: send a stream starting with "PROXY" and keep sending data (which does not contain a newline) until the target stops acknowledging.

In most real world circumstances, the actual risk is small since only trusted sources should be allowed to send proxy protocol headers. However, this is still a security issue and should be resolved.

Easiest fix: [HIDDEN] (the maximum v1 header size is 107 bytes). [HIDDEN].
