Optionally render nullable type
Instead of relying on the `field note` feature in DBML, we can also allow for static rendering of the ER diagrams in combination with nullable types by appending a marker to the type definition.

[According to DBML's schema](https://www.dbml.org/docs/#table-definition), we can append a `(?)` text suffix to the data types when they are nullable.

So, for example, when a command line argument is passed, FloorPlan can render
```
varchar(?)
```
for a nullable `TEXT` Room field.

<img width="320" alt="Screenshot 2020-04-07 at 13 45 05" src="https://user-images.githubusercontent.com/1541701/78665400-0aef2280-78d6-11ea-9bde-19c2db448af8.png">

### Additional contract requirements

- Provide the command-line option `--render-nullable-fields` to enable rendering nullable fields with a `(?)` suffix appended to their data types. When the option is omitted, nullable fields are rendered without that suffix.
