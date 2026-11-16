Rendering lines taller than the window height causes mis-renders
Currently, if you send more lines than the height of the window Bubble Tea rendering flips out. For cases like this we should _probably_ drop lines from the top and keep only the bottom ones.

Thanks to @fiws for flagging this and @maaslalani for reminding us about it.
