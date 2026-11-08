Make some of the optional flags required
**Is your feature request related to a problem? Please describe.**
I have many optional flags, but I want at least one of these to be required.

https://github.com/bader-nasser/pdftools#pdftools-extract:

```bash
pdftools extract -i <value> -o <value> [-D] [-s] [-c] [-f <value> | -p <value> | -d <value>] [-l <value>
    |  | ] [-q even|odd] [-r north|south|east|west|left|right|down] [-k]
```
I want to set one of flags: `-f`, `-l`, `-p` or `-d` to be required. By the way, `[-l <value>
    |  | ]` seems like a bug to me because I think it should look like `[-l <value> | -p <value> | -d <value>]` but I'm not sure!

**Describe the solution you'd like**
Maybe using a static property like:
```ts
static flagsRelations = FlagsRelations({
  required: {type: 'any', flags: [ 'firstPage', 'lastPage', 'pages', 'data' ]}
})
```

**Describe alternatives you've considered**
I tried to use `if` statements to make sure one of these flags is provided by the user!

```ts
firstPage = firstPage ?? lastPage;
lastPage = lastPage ?? firstPage;


if (firstPage && isUndefinedOrEmptyString(lastPage)) {
        lastPage = firstPage;
}


if (lastPage && isUndefinedOrEmptyString(firstPage)) {
        firstPage = lastPage;
}


if (
        isUndefinedOrEmptyString(firstPage) &&
        isUndefinedOrEmptyString(lastPage) &&
        isUndefinedOrEmptyString(pageRanges) &&
        isUndefinedOrEmptyString(data)
) {
        this.log(
                'This command is useless without using one of the following flags:',
        );
        this.log('--firstPage, --lastPage, --pageRanges, --data');
        this.log('See more help with --help');
} else {
       // ...
}
```

### Additional contract requirements

Flag options may include an `atLeastOne` array of flag names. This defines a collectively required group: parsing must reject input when none of the listed flags is supplied and accept input when one or more is supplied. The group may be declared on one of its member flags; it need not be repeated on every member.
