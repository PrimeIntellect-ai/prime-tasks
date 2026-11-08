[rewrite] Implement HTTP Guild Template API
Ref: https://discord.com/developers/docs/resources/guild-template

### Additional contract requirements

Expose the Guild Template API through the public `nyxx` library. `GuildTemplate` has `String code`, `GuildManager manager`, `String name`, `String? description`, `int usageCount`, `Snowflake creatorId`, `User creator`, `DateTime createdAt`, `DateTime updatedAt`, `Snowflake sourceGuildId`, `Guild serializedSourceGuild`, and `bool? isDirty` properties. Its constructor accepts each of those as a required named argument. Provide `use({required String name, ImageBuilder? icon}) -> Future<Guild>`, `fetch() -> Future<GuildTemplate>`, `sync() -> Future<GuildTemplate>`, `update(GuildTemplateUpdateBuilder builder) -> Future<GuildTemplate>`, and `delete() -> Future<GuildTemplate>` on the model.

Provide `GuildTemplateBuilder({required String name, String? description})` and `GuildTemplateUpdateBuilder({String? name, String? description})`.

`GuildManager` provides these operations and result types: `fetchGuildTemplate(String code) -> Future<GuildTemplate>`; `createGuildFromTemplate(String code, {required String name, ImageBuilder? icon}) -> Future<Guild>`; `listGuildTemplates(Snowflake id) -> Future<List<GuildTemplate>>`; `createGuildTemplate(Snowflake id, GuildTemplateBuilder builder) -> Future<GuildTemplate>`; `syncGuildTemplate(Snowflake id, String code) -> Future<GuildTemplate>`; `updateGuildTemplate(Snowflake id, String code, GuildTemplateUpdateBuilder builder) -> Future<GuildTemplate>`; and `deleteGuildTemplate(Snowflake id, String code) -> Future<GuildTemplate>`. These operations fetch a template by code, create a guild from a template with the requested details, list templates for a guild, create a template from supplied details, synchronize a template with its source guild, update a template with supplied changes, and delete a template. Return the corresponding parsed model, including the API response for deletion.
