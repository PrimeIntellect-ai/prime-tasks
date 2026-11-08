Schema should sort constants in dependency order
"Dependency order" meaning a sort of reverse topological sort - for any constant C in a schema's `constants` list, all constants referenced by C are guaranteed to precede it in the list.  This removes the need for codegen to figure out what order to emit things in.
