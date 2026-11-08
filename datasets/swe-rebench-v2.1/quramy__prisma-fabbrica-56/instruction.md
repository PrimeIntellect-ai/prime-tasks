Failed to generate when model without PK
**Describe the bug**
プライマリキーを持たないmodelの場合、npx prisma generate実行時に
```
Cannot read properties of undefined (reading 'name')
```
が発生し、generateに失敗してしまいます。

**To Reproduce**
後述するschema.prismaを用意し、npx prisma generateを実行で確認できます。
CompanyEmployeeに、@id、もしくは@@idでPKを設定すれば、発生しないことを確認しています。

**Expected behavior**
generateの正常終了

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
- `@prisma/client` version [4.6.1]
- TypeScript version [4.9.3]

**Additional context**
93247ecfd30e4ebd80dcee65acb6cab1154a1363
コードは最新のものから、特に変更を加えず確認しています。

### Additional contract requirements

- Add a public function `getIdFieldNames(model)` exported from the templates module (`packages/prisma-fabbrica/src/templates/index.ts`). Given a Prisma DMMF model, it returns a `string[]` of the model's identifier field names: the primary-key field list when the model defines one, otherwise a single-element array containing the name of the first field marked `@id` or `@unique`.
