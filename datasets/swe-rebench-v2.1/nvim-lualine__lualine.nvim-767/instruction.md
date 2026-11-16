Is there any ways to keep my lualine still?
if i switch to another window like 'NvimTree', i wish to keep my lualine in my main buffer, is there any  options can reach this? If we can keep lualine switching in main buffer except some window ( NvimTree ), that could be better :D

### Additional contract requirements

Users can configure `options.ignore_focus` as a list of filetypes. When focus moves into a window whose filetype is on that list, that window must not become the active lualine window; the active display remains with the most recently focused non-ignored window, and the ignored window is rendered as inactive. This allows file-tree and sidebar windows to avoid taking over the main buffer's active display.
