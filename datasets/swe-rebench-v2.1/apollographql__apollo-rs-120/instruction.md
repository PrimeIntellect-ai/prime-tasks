Ast errors: return an iterator
Follow up to [this comment](https://github.com/apollographql/router/pull/136#discussion_r756083538) we might want ast.errors() to return an Iterator.

@lrlna Since the current errors() method takes self by reference, I'll probably go with an `Iterator` and not an `IntoIterator`, what do you think ? :)
