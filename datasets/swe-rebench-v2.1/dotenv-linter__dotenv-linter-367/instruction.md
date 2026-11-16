v3 recursively lints backup files by default
I could be mistaken, but I don't think v2.x re-linted the backup files. I think that it ignored them.

Feel free to close this out if this is the desired behavior, but it seems like either these should be ignored by the date pattern, or should get a `.bak` extension and be excluded that way.

```bash
dotenv-linter fix
```

```
Fixing .env
Fixing .env_1610361920
Fixing .env_1610361920_1610361924
Fixing .env_1610361920_1610361924_1610361927
Original file was backed up to: ".env_1610361920_1610361924_1610361927_1610361929"

.env_1610361920_1610361924_1610361927:3 UnorderedKey: The AWS_REGION key should go before the AWS_SECRET_ACCESS_KEY key
```

### Additional contract requirements

- Backup files created by `dotenv-linter fix` must have the `.bak` extension (`bak`).
- Backup files must be excluded from linting, including recursive linting.
