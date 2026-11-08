category index generation seems wrong
I'm confused by the behavior of cobalt.rs' pagination_categories test. For example,  [my-fourth-blogpost.md](/cobalt-org/cobalt.rs/blob/master/tests/cmd/pagination_categories.in/posts/my-fourth-blogpost.md) has `categories: [cat1]` in its frontmatter, yet in the generated site this post appears in the [index page for category "catA"](/cobalt-org/cobalt.rs/blob/master/tests/cmd/pagination_categories.out/_dest/categories/cata/index.html) and no other category pages.

This is no priority for me as I'm probably going to switch to Cobalt's tags for the multiple un-nested "labels" in my Blogger blog that I want to static-site-ify.
