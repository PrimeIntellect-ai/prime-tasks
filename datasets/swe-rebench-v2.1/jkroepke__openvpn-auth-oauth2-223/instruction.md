Pass-Through : Send welcome message to client
### Problem Statement

When using the passthrough fonctionnality, the passthrough server don't transmit the welcome message send by the OpenVPN Management Interface.
For manual connection, it can be a bit confusing.
For script connection, it can be blocking because of the script waiting the welcome message, or the end of it, and never receive it.


### Proposed Solution

[HIDDEN]

### Additional information

Example :
Following script is used to send command to OpenVPN Management Interface (Component of https://github.com/d3vilh/openvpn-ui) :
https://github.com/d3vilh/openvpn-server-config/blob/main/server/mi/client.go#L98

At line 98, it read the welcome message before sending command, but never receive it from the PassThrough
`buf := bufio.NewReader(conn)
	buf.ReadString('\n') //read welcome message
	err = SendCommand(conn, cmd)`


### Acceptance Criteria

_No response_

### Additional contract requirements

- A client connecting through pass-through must receive the OpenVPN Management Interface welcome message before it needs to send a command.
