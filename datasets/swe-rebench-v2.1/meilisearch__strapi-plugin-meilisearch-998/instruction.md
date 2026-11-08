Meilisearch update failure with draftAndPublish enabled: Transaction query already complete
**Description:**
When updating / adding an item in the Meilisearch plugin with the draftAndPublish option enabled for a content type, the item is removed from Meilisearch, and I receive the following error:

```shell
error: Meilisearch could not add entry with id: 9: Transaction query already complete, run with DEBUG=knex:tx for more info
```

This issue only occurs when the draftAndPublish feature is enabled. When I disable this option, the update works as expected, and the item is correctly uploaded to Meilisearch.

**Expected behavior:**
The item should be updated in Meilisearch without issues.

**Current behavior**
The item is removed from Meilisearch, and the error is displayed. However, if the "Update" button in the plugin is pressed, the items are correctly synchronized. This likely happens because all items are deleted first and then added again during the synchronization process, bypassing the issue.

**Environment (please complete the following information):**
- node
- Meilisearch version:
- strapi-plugin-meilisearch version: 0.13.0 /  0.13.1
- Browser: brave
- Strapi version:  5.6.0
