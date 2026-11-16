Throws error on providing a file that doesn't exist with start command
`fastify start <file>` throws an error if the respective file doesn't exist:-

![Screenshot from 2019-06-22 23-02-21](https://user-images.githubusercontent.com/25279263/59967020-2acd7980-9542-11e9-934b-581a3e98475d.png)


It seems that this was intentional as from:-
 https://github.com/fastify/fastify-cli/blob/f8ca00c1066c779b822b315a07162098fe41b161/start.js#L91

IMO it is good to warn the user appropriately :thinking:

### Additional contract requirements

When the start file does not exist, `fastify start` must not throw. Instead it must
emit a warning message that contains the exact text `<file> doesn't exist within <cwd>`,
where `<file>` is the start file path exactly as passed on the command line and `<cwd>`
is the current working directory. For example, running `fastify start ./data/not-found.js`
from `/app` must produce a warning containing `./data/not-found.js doesn't exist within /app`.
