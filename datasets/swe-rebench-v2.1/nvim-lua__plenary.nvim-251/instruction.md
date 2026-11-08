Path:normalize() breaks when path contains ...
As an example, a NextJS application can have files named in this format `pages/api/user/[...ids].ts`. Normalizing this path causes it to come back prefixed with the root (`/`). This is causing issues in telescope where it can't open files with this naming style.

See: https://github.com/nvim-telescope/telescope.nvim/issues/1171

I think this is because of this line: https://github.com/nvim-lua/plenary.nvim/blob/6bb0e09030a7c2af19bf288088ca815228de9429/lua/plenary/path.lua#L86

I have a possible fix and test (other tests still pass) which I'll create PR for
