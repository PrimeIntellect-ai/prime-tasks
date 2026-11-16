Server only returns `FixAll` actions even when client requests both `FixAll` & `QuickFixes`
> [!WARNING]
> I've created a Zed extension that relies on the server from this repo. What I'm reporting as a "bug" here does not exist with VSCode but I assume the server should be more "client agnostic" (which is debatable since this project is initially for VSCode).
If you don't agree with that, feel free to close this issue & the associated PR, I'll handle it in a fork.

This Issue can be seen as a bug report or a feature request because it aims at changing the behavior documented here: https://github.com/stylelint/vscode-stylelint/blob/main/src/server/modules/code-action.ts#L215.

## The issue

- When the requested actions include FixAll, the server ignores other requested actions and only returns the FixAll action,
   - The part of the source code responsible for this behavior is here: https://github.com/stylelint/vscode-stylelint/blob/main/src/server/modules/code-action.ts#L215.
- It does match the VSCode behavior because quickfixes and source / document actions are separate features, triggered separately,
- But some clients (like Zed), send requests for both Quickfixes and source / document actions (FixAll) within the same `only` code actions array.

## The suggested change

- Let the server return all the requested code action types (fix all, quickfixes) at the same time because it's up to the client to decide what it needs.
- This shouldn't impact VSCode because quickfixes and fix all are requested separately (the `only` array just includes `fixAll` or `quickfixes` but not both at the same time (I'm not sure, I just tested this theory quickly, I could definitely be wrong about that)
