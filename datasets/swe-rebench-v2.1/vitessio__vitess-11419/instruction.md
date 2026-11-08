Bug Report: select on alias result in Unknown column \'xx\' in \'field list\' errors
### Overview of the Issue

I have a query with `SELECT (alias) as ..` that doesn't work. The same query works in v5 but not v13. We are jumping several versions and I am not sure where it exactly broke.

Slack conversation: https://vitess.slack.com/archives/C0PQY0PTK/p1663334176821599



### Reproduction Steps

VSchema:
```
tables: <
  key: "folders"
  value: <
    auto_increment: <
      column: "id"
      use_v_tickets: true
    >
  >
>
tables: <
  key: "form_field_maps"
  value: <
    auto_increment: <
      column: "db_id"
      use_v_tickets: true
    >
  >
>
tables: <
  key: "permissions"
  value: <
    auto_increment: <
      column: "id"
      use_v_tickets: true
    >
  >
>
```

Schema:
```
CREATE TABLE `forms` (
  `portalId` bigint(20) unsigned NOT NULL,
  `formType` tinyint(3) unsigned NOT NULL,
  `createdAt` bigint(20) NOT NULL,
  `updatedAt` bigint(20) unsigned NOT NULL,
  `deletedAt` bigint(20) unsigned DEFAULT NULL,
  `active` tinyint(1) NOT NULL,
  `campaignGuid` char(36) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `migratedFrom` varchar(45) DEFAULT NULL,
  `parentId` int(10) unsigned NOT NULL DEFAULT '0',
  `jsonPublished` json DEFAULT NULL,
  `jsonDraft` json DEFAULT NULL,
  `visibleToAll` tinyint(1) unsigned DEFAULT NULL,
  `formGuid` char(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `customUid` char(36) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `businessUnitId` bigint(20) unsigned NOT NULL DEFAULT '0',
  `portableKey` char(36) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  PRIMARY KEY (`formGuid`),
  UNIQUE KEY `unique_formGuid` (`formGuid`),
  UNIQUE KEY `unique_customUid` (`customUid`,`portalId`),
  UNIQUE KEY `unique_portal_id_portable_key` (`portalId`,`portableKey`),
  KEY `portal_id_updated_at_index` (`portalId`,`updatedAt`),
  KEY `portal_id_name_index` (`portalId`,`name`),
  KEY `createdAt_portalId` (`createdAt`,`portalId`),
  KEY `portalId_active_formType` (`portalId`,`active`,`formType`),
  KEY `parentId` (`parentId`,`portalId`,`active`),
  KEY `portalId_parentId_active_formType` (`portalId`,`parentId`,`active`,`formType`),
  KEY `deleted_at_idx` (`deletedAt`),
  KEY `portal_id_portable_key` (`portalId`,`portableKey`),
  KEY `portal_id_business_unit_id` (`portalId`,`businessUnitId`),
  KEY `portal_id_active_form_guid` (`portalId`,`active`,`formGuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8
```

Query:
```
SELECT /*+ MAX_EXECUTION_TIME(30000) */(SELECT COUNT(formGuid) from forms WHERE active = 1 AND portalId = 123 AND formType IN (_formTypes_0:0,__formTypes_1:2)
AND name LIKE CONCAT('%',Folder,'%')) as formsTotal,
(SELECT COUNT(id) from folders WHERE deletedAt = 0 AND portalId = 123 AND name LIKE CONCAT('%',Folder,'%')) as foldersTotal,
(SELECT formsTotal) as formsInFolderTotal
```

if i instead do this, it works
```
SELECT /*+ MAX_EXECUTION_TIME(30000) */(SELECT COUNT(formGuid) from forms WHERE active = 1 AND portalId = 123 AND formType IN (_formTypes_0:0,__formTypes_1:2)
AND name LIKE CONCAT('%',Folder,'%')) as formsTotal,
(SELECT COUNT(id) from folders WHERE deletedAt = 0 AND portalId = 123 AND name LIKE CONCAT('%',Folder,'%')) as foldersTotal,
(SELECT /*+ MAX_EXECUTION_TIME(30000) */(SELECT COUNT(formGuid) from forms WHERE active = 1 AND portalId = 123 AND formType IN (_formTypes_0:0,__formTypes_1:2)
AND name LIKE CONCAT('%',Folder,'%')) as formsInFolderTotal
```

### Binary Version

```
v13.0.0, commit bc4a960
```


### Operating System and Environment details

```
Can reproduce on both macos and linux, running unit tests in Java
```


### Log Fragments

```sh
Vitess vtgate error: message: "target: test_db_Fi4w2Y.0.primary: vttablet: rpc error: code = NotFound desc = Unknown column \'formsTotal\' in \'field list\' (errno 1054) (sqlstate 42S22) (CallerID: unsecure_grpc_client): Sql: \"select /*+ MAX_EXECUTION_TIME(30000) */ (select COUNT(formGuid) from forms where active = :vtg1 and portalId = :v1 and businessUnitId = :v2 and formType in (:v3, :v4) and `name` like CONCAT(:vtg2, :v5, :vtg2)) as formsTotal, (select COUNT(id) from folders where deletedAt = :vtg3 and portalId = :v6 and `name` like CONCAT(:vtg2, :v7, :vtg2)) as foldersTotal, formsTotal as formsInFolderTotal from dual\", BindVars: {v1: \"type:INT64 value:\\\"123\\\"\"v2: \"type:INT64 value:\\\"1\\\"\"v3: \"type:INT64 value:\\\"0\\\"\"v4: \"type:INT64 value:\\\"2\\\"\"v5: \"type:VARCHAR value:\\\"unit\\\"\"v6: \"type:INT64 value:\\\"123\\\"\"v7: \"type:VARCHAR value:\\\"unit\\\"\"vtg1: \"type:INT64 value:\\\"1\\\"\"vtg2: \"type:VARCHAR value:\\\"%\\\"\"vtg3: \"type:INT64 value:\\\"0\\\"\"}"
code: NOT_FOUND
 [statement:"SELECT(SELECT COUNT(formGuid) from forms WHERE active = 1 AND portalId = :portalId AND /* FILTER:businessUnitId [businessUnitId = :businessUnitId AND ] */formType IN (<formTypes>) AND name LIKE CONCAT('%',:searchName,'%')) as formsTotal,(SELECT COUNT(id) from folders WHERE deletedAt = 0 AND portalId = :portalId AND name LIKE CONCAT('%',:searchName,'%')) as foldersTotal,(SELECT formsTotal) as formsInFolderTotal", located:"SELECT(SELECT COUNT(formGuid) from forms WHERE active = 1 AND portalId = :portalId AND /* FILTER:businessUnitId [businessUnitId = :businessUnitId AND ] */formType IN (:__formTypes_0,:__formTypes_1) AND name LIKE CONCAT('%',:searchName,'%')) as formsTotal,(SELECT COUNT(id) from folders WHERE deletedAt = 0 AND portalId = :portalId AND name LIKE CONCAT('%',:searchName,'%')) as foldersTotal,(SELECT formsTotal) as formsInFolderTotal", rewritten:"SELECT /*+ MAX_EXECUTION_TIME(30000) */(SELECT COUNT(formGuid) from forms WHERE active = 1 AND portalId = ? AND businessUnitId = ? AND formType IN (?,?) AND name LIKE CONCAT('%',?,'%')) as formsTotal,(SELECT COUNT(id) from folders WHERE deletedAt = 0 AND portalId = ? AND name LIKE CONCAT('%',?,'%')) as foldersTotal,(SELECT formsTotal) as formsInFolderTotal", arguments:{ positional:{}, named:{portalId:123,searchName:'unit',__formTypes_0:0,__formTypes_1:2,businessUnitId:1}, finder:[]}]
```

### Additional contract requirements

- The rewritten query must preserve the SELECT-list scalar subquery that references an earlier SELECT alias. For `select 1 as x, (select x)`, the second select expression must remain a subquery; it must not be rewritten into a bare column reference to the alias.
