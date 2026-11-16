filter out parent page from ChildrenQuery response
## Type of Change
- [ ] New Feature Request
- [ ] Documentation / Website
- [x] Improvement / Suggestion
- [ ] Bug
- [ ] Other (please clarify below)

## Summary
Right now `ChildrenQuery` is returning the [index.md](https://github.com/ProjectEvergreen/greenwood/blob/release/0.5.0/packages/cli/test/unit/data/schema/graph.spec.js#L68) as part of the array of pages returned, which is effectively the parent route.  I think in this case, it doesn't make sense to return the parent if you are asking for the children, or else to render the children as a list, you'll have to exclude the parent, e.g. _${parent}/index.md_


[HIDDEN]

## Details
Given a structure like this
```shell
pages/
  blog/
    first-post.md
    index.md
    second-post.md
    third-post.md
```

And render it like this
```js
render() {
  return html`
    <ul>
      ${posts.map((post) => {
        return html`
          <li>
            <a href="${post.link}" title="Click to read my ${post.title} blog post">${post.title}</a>
          </li>
        `;
       })}
     </ul>
  `
}
```

You'll have to something like this in your component
```js
class BlogPostsTemplate extends LitElement {
  ...

  async connectedCallback() {
    super.connectedCallback();
    const response = await client.query({
      query: ChildrenQuery,
      variables: {
        parent: 'blog'
      }
    });

    this.posts = response.data.children.filter(post => {
      return post.filePath.indexOf('/blog/index') < 0;
    });
  }
```

Or else you'll have a list like this, when you probably only want the posts themselves
1. First Post
1. Blog
1. Second Post
1. Third Post

### Additional contract requirements

- For a given parent, `ChildrenQuery` must return its child pages without including the page represented by that parent's `index.md`.
