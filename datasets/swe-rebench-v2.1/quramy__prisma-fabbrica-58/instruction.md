Cannot convert when composite unique key and Primary Key are not set
**Describe the bug**
https://github.com/Quramy/prisma-fabbrica/issues/55

The above issue you responded to.
I am still experiencing the same problem with the schema.prisma described in the issue.
Sorry for the lack of explanation.

対応いただいた上記issueですが、
issueに記載したschema.prismaで現在も同様の現象が発生しています。
説明不足で申し訳ございません。

```sh
$ npx prisma generate
Prisma schema loaded from prisma/schema.prisma
Error:
✔ Generated Prisma Client (4.6.1 | library) to ./../../node_modules/@prisma/client in 58ms

Cannot read properties of undefined (reading 'name')
```

**To Reproduce**
Define composite unique key with @@unique
&&
Occurs when Primary Key does not exist for a model.
If @@id and @@id are added, it will not occur.

@@uniqueで複合ユニークキーを定義
&&
Primary Keyが存在しないmodelの場合に発生。
@id, @@idを追加すれば発生しない。

**Expected behavior**
Successful fabbrica conversion

正常にfabbricaの変換が行われる

**Your Schema**

```
// Paste schema.prisma file.
model Company {
  id    String @id
  name  String
  companyEmployees CompanyEmployee[]
}

model Employee {
  id        String   @id
  name      String
  companyEmployees CompanyEmployee?
}

model CompanyEmployee {
  company   Company  @relation(fields: [companyId], references: [id])
  companyId String
  employee  Employee @relation(fields: [employeeId], references: [id])
  employeeId String @unique

  @@unique([companyId, employeeId])
}
```

**Environment (please complete the following information):**

- Database kind [sqlite]
- Node.js version [18.11.0]
- @prisma/client version [4.6.1]
- TypeScript version [4.9.3]

**Additional context**
Add any other context about the problem here.

Please put gist URL including generated .js and .d.ts if you can :pray:
