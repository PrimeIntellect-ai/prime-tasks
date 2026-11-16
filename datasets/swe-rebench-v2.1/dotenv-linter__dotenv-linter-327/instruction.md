Linter rechecks files if they were listed more than once
Create 3 files in one dir:
```
$ mkdir -p /tmp/project
$ for f in a b c; do echo "ohno" > /tmp/project/.env.$f; done
$ tree -a /tmp/project
/tmp/project
├── .env.a
├── .env.b
└── .env.c
```

Listing whole dir twice leads to each file being checked twice:
```
$ cargo run -- /tmp/project/ /tmp/project/
    Finished dev [unoptimized + debuginfo] target(s) in 0.01s
     Running `target/debug/dotenv-linter /tmp/project/ /tmp/project/`
../../../../tmp/project/.env.a:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.b:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.c:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.a:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.b:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.c:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign

Found 6 problems
```

Listing file `.env.a` and whole dir works as expected:
```
$ cargo run -- /tmp/project/ /tmp/project/.env.a
    Finished dev [unoptimized + debuginfo] target(s) in 0.03s
     Running `target/debug/dotenv-linter /tmp/project/ /tmp/project/.env.a`
../../../../tmp/project/.env.a:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.b:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.c:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign

Found 3 problems
```
Hovewer, listing file `.env.b` and whole dir leads to the file being checked twice:
```
$ cargo run -- /tmp/project/ /tmp/project/.env.b
    Finished dev [unoptimized + debuginfo] target(s) in 0.02s
     Running `target/debug/dotenv-linter /tmp/project/ /tmp/project/.env.b`
../../../../tmp/project/.env.b:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.a:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.b:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign
../../../../tmp/project/.env.c:1 KeyWithoutValue: The ohno key should be with a value or have an equal sign

Found 4 problems
```

I guess the issue is here https://github.com/dotenv-linter/dotenv-linter/blob/281a2030aa66bd3d3dcbbabb1636659548e96a98/src/lib.rs#L101-L103
[HIDDEN]

### Additional contract requirements

- Each file selected through repeated or overlapping input paths—including a directory and a file it contains—is checked at most once per invocation.
- When reporting diagnostics for multiple files, order them by ascending lexicographic file path.
