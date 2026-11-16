ensureFileSync vs ensureDirSync
When `ensureDirSync` is called on a folder that already exists as a file, `EEXIST` is thrown as expected.

When `ensureFileSync` is called on a file that already exists as a folder nothing is thrown.

Should not the two behaviours be the same? IMHO either both should throw or none of them should throw.
