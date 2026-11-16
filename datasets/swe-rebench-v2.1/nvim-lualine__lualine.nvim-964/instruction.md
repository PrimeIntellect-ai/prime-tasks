(ready to do PR) Feat: add option to draw component even if it's empty, just for the separator
It would be nice if there would be option for unconditionally drawing component even if it's empty just for the separator.

### Motivation

I want be able to include decorative blocks in the statusline like this:
![screenshot_2023_02_11_16_58_29](https://user-images.githubusercontent.com/47556468/218265726-68b384b6-1810-4d03-ad4c-2cbc21a7b5a5.png)
(the one after git branch segment)

I was able to do it however it's not what I exactly wanted because of extra space I had to add.
Ideally I'd like to be able to make it look like that:
![screenshot_2023_02_11_17_06_41](https://user-images.githubusercontent.com/47556468/218265854-48a78636-608d-4e6f-88a0-0f35f40fb768.png)
As you can see it is thinner now because there's no extra space.

<!-- Explain why you think it should be included in lualine.-->
I think it might be useful to other people and it's one line of code to add.

### Additional contract requirements

- Add a component option named `draw_empty`. When enabled, an empty component is still drawn so its configured separator is rendered.
