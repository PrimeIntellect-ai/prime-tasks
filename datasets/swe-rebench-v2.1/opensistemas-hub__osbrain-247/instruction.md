Bind with differt ip host
HI,
i have found a problem when bind a socket whith a different IP host and transfert tcp. If in bind a socket whit an IP whitout oprt, it returns as address 'localhost'., but if bind with IP and port, it return correctly the address with my IP and port. I think that the problem is in the procedure _bind_socket of Agent class ( it lose the information about the host, [HIDDEN]

Regards !

### Additional contract requirements

- When binding a TCP socket with a host supplied but no port, the resolved address must retain the supplied host rather than use the agent's default host.
