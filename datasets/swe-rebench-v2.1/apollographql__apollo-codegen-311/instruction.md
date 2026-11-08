flow-modern target fails on some multiline comments
Using version 0.18.0 with `--target flow-modern`, I get this error:

```
TypeError: Cannot read property 'trim' of undefined
    at Printer.fixCommas (./node_modules/apollo-codegen/src/javascript/flow/printer.ts:87:24)
    at printQueue.reduce (./node_modules/apollo-codegen/src/javascript/flow/printer.ts:19:36)
```

I added this debugging,
```
                const [contents, comment] = currentLineContents.split('//');
                if (!comment) {
                  console.log({contents, comment, currentLineContents, currentLine, strippedNextLine, commentColumn, documentPart});
```
And that outputs:
```
{ contents: 'TODO make this available under another key with a Date type',
  comment: undefined,
  currentLineContents: 'TODO make this available under another key with a Date type',
  currentLine: 21,
  strippedNextLine: ',',
  commentColumn: -1,
  documentPart: 'export type AdminPeopleTab_organizations_class_owners = {\n  __typename: "ClassMembership",\n  id: number // The membership ID.\n  ,\n  group_id: number // The group ID for this membership.\n  ,\n  can_become_owner: boolean // True if this user may be promoted to an owner.\n  ,\n  can_unsubscribe: boolean // True if you may unsubscribe this user from the class\n  ,\n  can_chat: boolean // True if you may initiate a chat with this user\n  ,\n  chat_eligibility_state: ChatEligibilityState // The chat eligibility state of the user, e.g. eligible, pending, under_13\n  ,\n  role: ClassMembershipRole // The member\'s role in the class\n  ,\n  tag: ?string // An optional tag to show in the member list.\n  ,\n  query_key: string // The string to match client side filtering against.\n  ,\n  created_at: ?string // When the user joined\nTODO make this available under another key with a Date type\n  ,\n  user: AdminPeopleTab_organizations_class_owners_user,\n  org_affiliation_view: ?AdminPeopleTab_organizations_class_owners_org_affiliation_view,\n  permissions: ?AdminPeopleTab_organizations_class_owners_permissions,\n};' }
TypeError: Cannot read property 'trim' of undefined
```

So it appears to be choking on the multiline description, which in our JSON schema is
```json
              "description": "When the user joined\nTODO make this available under another key with a Date type",
```

I see that the repo has an explicit test for multiLine which is passing. My guess as to why this one isn't is that the `AdminPeopleTab` query uses a fragment. Maybe there's some interaction with the `.gql` loader?

### Additional contract requirements

- For this case, generated Flow output must include `multiLine: ?string, // This is a multi-line comment.`
