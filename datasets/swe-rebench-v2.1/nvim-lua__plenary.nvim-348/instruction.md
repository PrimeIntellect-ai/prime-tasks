Issue with one-character directory names
### Description

Selecting and opening _anything_ using Telescope leads to an error `E5108 ... We couldn't mkdir: /Users/.local`.  It seems that this stems from the function `action_state.get_current_history()`, but I'm not sure what is happening.  Opening up Telescope to use it seems fine, and `:checkhealth telescope` doesn't flag anything, but when I try to use it to do anything, it errors.

This happens for me even with the most minimal possible config, as provided.  I really have no idea what could be going on.  It shouldn't be doing anything in`/Users/.local`. This directory doesn't exist, and I don't think it should be trying to make it.  Instead it should probably be trying to access something in `/Users/myusername/.local`, I imagine, since I think that's the correct default location on macOS.  For instance, when I run `:echo stdpath("data")` I get back `/Users/myusername/.local/share/nvim`.

- Is there some new recently added option for configuring the where the .local directory should be?  Is there perhaps an error in the error message itself?
- I'll note I updated Telescope for the first time in a little while (I don't know what version I am coming from before, but I just installed things fresh on a new computer in February, so it wasn't very old, but I just updated to the most recent, and this bug started).

I wish I could troubleshoot further but I'm a little lost.  Any help would be appreciated!

**Edit:** my username is one character long. It seems this is causing the issue. For some reason for any one-character directory like `/Users/x/.local` it gets interpreted as `/Users/.local` by plenary.path, somehow.

### Neovim version

```markdown
NVIM v0.6.1
Build type: Release
LuaJIT 2.1.0-beta3
Compiled by brew@HMBRW-A-001-M1-004.local
```


### Operating system and version

macOS 12.3.1 (21E258)

### checkhealth telescope

```markdown
telescope: require("telescope.health").check()
========================================================================
## Checking for required plugins
  - OK: plenary installed.
  - OK: nvim-treesitter installed.

## Checking external dependencies
  - OK: rg: found ripgrep 13.0.0
  - OK: fd: found fd 8.3.2

## ===== Installed extensions =====
```


### Steps to reproduce

1. run `nvim -nu minimal.lua` (it is the absolute most minimal minimal config; no additional plugins or extensions are needed)
2. in nvim open any telescope picker, for instance run `:Telescope`
3. select anything in the Results list, for instance, `buffers`, and press <kbd>enter</kbd>

### Expected behavior

The selected item should open.

For instance, if you ran `:Telescope` and selected `buffers`, you should see the buffers picker.  If you ran `:Telescope find_files` and selected a file, that file should open.

### Actual behavior

No matter what item I am selecting, whether it's a file from the `find_files`, or a telescope command from `:Telescope`, I get the same following error:

```
E5108: Error executing lua ...site/pack/packer/start/plenary.nvim/lua/plenary/path.lua:467: We couldn't mkdir: /Users/.local
stack traceback:
        [C]: in function 'error'
        ...site/pack/packer/start/plenary.nvim/lua/plenary/path.lua:467: in function 'mkdir'
        ...site/pack/packer/start/plenary.nvim/lua/plenary/path.lua:600: in function 'touch'
        ...r/start/telescope.nvim/lua/telescope/actions/history.lua:171: in function 'init'
        ...r/start/telescope.nvim/lua/telescope/actions/history.lua:77: in function 'handler'
        ...ker/start/telescope.nvim/lua/telescope/actions/state.lua:47: in function 'get_current_history'
        ...cker/start/telescope.nvim/lua/telescope/actions/init.lua:189: in function <...cker/start/telescope.nvim/lua/telescope/actions/init.lua:188>
        ...packer/start/telescope.nvim/lua/telescope/actions/mt.lua:58: in function 'key_func'
        ...k/packer/start/telescope.nvim/lua/telescope/mappings.lua:242: in function 'execute_keymap'
        [string ":lua"]:1: in main chunk
```

### Minimal config

```Lua
vim.cmd [[set runtimepath=$VIMRUNTIME]]
vim.cmd [[set packpath=/tmp/nvim/site]]
local package_root = '/tmp/nvim/site/pack'
local install_path = package_root .. '/packer/start/packer.nvim'
local function load_plugins()
  require('packer').startup {
    {
      'wbthomason/packer.nvim',
      {
        'nvim-telescope/telescope.nvim',
        requires = {
          'nvim-lua/plenary.nvim',
          { 'nvim-telescope/telescope-fzf-native.nvim', run = 'make' },
        },
      },
    },
    config = {
      package_root = package_root,
      compile_path = install_path .. '/plugin/packer_compiled.lua',
      display = { non_interactive = true },
    },
  }
end
_G.load_config = function()
  require('telescope').setup()
  require('telescope').load_extension('fzf')
end
if vim.fn.isdirectory(install_path) == 0 then
  print("Installing Telescope and dependencies.")
  vim.fn.system { 'git', 'clone', '--depth=1', 'https://github.com/wbthomason/packer.nvim', install_path }
end
load_plugins()
require('packer').sync()
vim.cmd [[autocmd User PackerComplete ++once echo "Ready!" | lua load_config()]]
```
