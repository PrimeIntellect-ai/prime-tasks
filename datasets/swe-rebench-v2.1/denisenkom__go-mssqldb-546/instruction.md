Azure Active Directory Authentication is not supported?
Hi,

I am able to connect to Azure database using SQL authentication but when I use [Azure AD](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-aad-authentication) credentials I receive TLS handshake error when pinging the database:
`Cannot read handshake packet: read tcp: wsarecv: An existing connection was forcibly closed by the remote host.`

Connection String:
`sqlserver://user:pass@database.windows.net:1433?app+name=MyAppName&database=dbname&encrypt=true&hostNameInCertificate=%2A.database.windows.net&trustservercertificate=true`

Is the Azure AD supported or not?

Thanks

### Additional contract requirements

Implement Azure Active Directory access-token authentication for Azure SQL connections. Expose `NewAccessTokenConnector(dsn string, tokenProvider func() (string, error)) (driver.Connector, error)` so applications can provide a fresh access token when a connection is created. The connector must use the supplied token for the Azure SQL login exchange; token-provider errors must be returned from the connection attempt.
