page.fileSlug and directory index files: date doesn't get stripped out
**Describe the bug**

Currently, my post Markdown files follow the `YYYY-MM-DD-file-slug.md` convention and are located immediately under a `_posts` directory. [I aggregate all of these files into a custom `posts` collection](https://github.com/AleksandrHovhannisyan/aleksandrhovhannisyan.com/blob/master/config/utils/index.js#L6) using 11ty's collection API:

```js
const getAllPosts = (collection) => {
  return collection.getFilteredByGlob(`${dir.input}/_posts/*.md`);
};
```

I also have the following `_posts.json` at the root of my `_posts` directory to apply common front matter to each post; of note is the `permalink` value, which uses `page.fileSlug`:

```json
{
  "layout": "post",
  "permalink": "/blog/{{ page.fileSlug }}/",
  "isBlogPage": true,
  "isPost": true
}
```

[As expected](https://www.11ty.dev/docs/data-eleventy-supplied/#fileslug), `page.fileSlug` strips out the dates from my file names. So `YYYY-MM-DD-file-slug` maps to the URL `/blog/file-slug/`. This is all working as intended.

![image](https://user-images.githubusercontent.com/19352442/130438909-f6075379-6745-4f0f-8be1-301a3d601c30.png)

Now, I want to restructure my blog to co-locate images and posts under the same directory using index files. So instead of containing the Markdown posts as immediate children, my `_posts` directory will now contain nested directories of the form `YYYY-MM-DD-file-slug`, and nested inside each directory will be a corresponding `index.md` for the post and an `images` directory for any images.

I've adjusted my config to create posts using `collection.getFilteredByGlob('src/_posts/**/*.md')`. This works. However, per the examples in the documentation linked above, I would expect the date to also get stripped out from the directory name, but it doesn't. So now, my post permalinks are `/blog/YYYY-MM-DD-file-slug/` rather than `/blog/file-slug/`:

![image](https://user-images.githubusercontent.com/19352442/130439252-e73f6c53-c05e-4149-bcdd-a5c673e0dfd9.png)

**To Reproduce**

1. Clone my site: https://github.com/AleksandrHovhannisyan/aleksandrhovhannisyan.com
2. Check out the branch `co-located-images`:
3. Run `yarn` to install dependencies.
4. Run `yarn serve:eleventy` to start up just the 11ty server.
5. When it finishes, navigate to `localhost:4001`. Click any post, and observe that its URL contains the date in the slug.

**Expected behavior**
When using index files in directories, the date should get stripped out from the directory name in `fileSlug`.

**Environment:**

- OS and Version: Windows 10
- Eleventy Version: 0.12.1
