Blog.Blog.Blog.Post.__struct__/1 is undefined, cannot expand struct Blog.Blog.Blog.Post
### Environment

* Elixir version (elixir -v): 1.8.0
* Phoenix version (mix deps): 1.4.0
* NodeJS version (node -v): 8.8.1
* NPM version (npm -v): 5.4.2
* Operating system: macOS 10.14.2

### Expected behavior

    $ mix phx.new blog
    $ cd blog
    $ mix ecto.create
    $ mix phx.gen.html Blog Post posts title body:text
    $ vim lib/blog_web/router.ex # adding the route
    $ mix ecto.migrate

### Actual behavior

    $ mix phx.new blog
    $ cd blog
    $ mix ecto.create
    $ mix phx.gen.html Blog Post posts title body:text
    $ vim lib/blog_web/router.ex # adding the route
    $ mix ecto.migrate
    Compiling 6 files (.ex)

    == Compilation error in file lib/blog_web/controllers/post_controller.ex ==
    ** (CompileError) lib/blog_web/controllers/post_controller.ex:13: Blog.Blog.Blog.Post.__struct__/1 is undefined, cannot expand struct Blog.Blog.Blog.Post
        lib/blog_web/controllers/post_controller.ex:12: (module)
        (stdlib) erl_eval.erl:680: :erl_eval.do_apply/6

If `mix phx.new blog` and `mix phx.gen.html Blog Post posts title body:text` don't mix then there should be an error message from `mix phx.gen.html`. Alternatively it should work without the error afterwords.
