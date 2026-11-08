Misalignment in socket authentication documentation
Hi,

There is some misalignment in the documentation for socket authentication in the channels guide and in the generated `socket.js` file from `phx.gen.socket`.

The guide suggests using the transport agnostic method of sending the user token through a header, while the file suggests using the older approach of sending it as a query parameter.

https://github.com/phoenixframework/phoenix/blob/69e2cfa13b94e75bb749bd912f3727e9e4fd410c/guides/real_time/channels.md?plain=1#L453-L457

https://github.com/phoenixframework/phoenix/blob/2875c54cddec2fc45258baee9a84cc8193cad541/priv/templates/phx.gen.socket/socket.js#L7-L9

### Additional contract requirements

- The generated client socket code must pass the user token through the header-based `authToken` option, rather than as a query parameter.
