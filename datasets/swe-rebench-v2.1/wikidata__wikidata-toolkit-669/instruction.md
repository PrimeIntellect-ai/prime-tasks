Generic method to create new EntityDocument in WikibaseDataEditor
We currently have generic methods to perform an EntityUpdate on the target Wikibase, but to create new entities we only have methods which depend on the entity type. We could add a generic version of it:
`WikibaseDataEditor::createEntityDocument(EntityDocument entityDocument, String summary, List<String> tags)`.

This would fail for entity types which cannot be created in this way (such as `MediaInfoDocument`).
