Allow paths to start with `::`
[Discovered while working on #315 and #327.]

At the moment `{{ std::string::String::new()}}` works but `{{ ::std::string::String::new() }}` doesn't.
