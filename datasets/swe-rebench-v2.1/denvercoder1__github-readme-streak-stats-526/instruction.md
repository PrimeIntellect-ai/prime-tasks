add color change of excluded days
## Is your feature request related to a problem? Please describe.
I would like to request a feature related to customizing the generated  streak-card. Currently, there is no straightforward way to change the color of `exclude_days` independently. When I try to change the color of `exclude_days` by modifying the `dates` tag, it changes the color of all the dates. However, I want my dates to remain white while keeping `exclude_days` in red, matching the color of my streak.

## Describe the solution you'd like
I would appreciate it if there could be an option to customize the color of `exclude_days` separately from the other dates. This would allow me to set my dates to white while keeping `exclude_days` in red.

## Describe alternatives you've considered
As a workaround, I have tried modifying the `dates` tag to match the color of my streak (e.g., `ff7b72`), but this changes the color of all the dates instead of just the `exclude_days`. Therefore, I haven't found a suitable alternative solution yet. It would be helpful to have the ability to specify the color for exclude_days independently, perhaps by introducing a new tag such as exclude_days_colors.

## Additional context
I have attached screenshots below to provide additional context:

1. The current appearance of the generated card with the `dates` color set to `ffffff` (white)

![Captura de tela 2023-05-25 084949](https://github.com/DenverCoder1/github-readme-streak-stats/assets/88681055/4f2cf1d3-97b2-4552-a73f-1f0ded0fbfe9)

2. The modified appearance of the generated card with the `dates` color set to `ff7b72` (red) to match my streak color

![Captura de tela 2023-05-25 085026](https://github.com/DenverCoder1/github-readme-streak-stats/assets/88681055/645919d1-4a1c-43ca-b698-6dc128996324)

3. An illustrative image demonstrating how I would like the card to appear, with my dates in white and `exclude_days` in red.

![Streak_card](https://github.com/DenverCoder1/github-readme-streak-stats/assets/88681055/23268d2d-32ff-4fac-9c20-e865e4b6295d)

I hope this feature can be considered for implementation. Thank you for your attention to this matter.

### Additional contract requirements

The excluded-days color is exposed as a new query parameter named `excludeDaysLabel`. It is a theme color parameter: every theme defines it, it can be overridden per request like `dates`, and the default theme defines it as `#464646`. The excluded days text is rendered with this color as its `fill`.
