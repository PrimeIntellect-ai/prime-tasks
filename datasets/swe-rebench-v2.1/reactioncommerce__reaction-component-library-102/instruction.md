Price Component needs ability to render compareAtPrice above displayPrice
@nnnnat commented on [Tue Jun 26 2018](https://github.com/reactioncommerce/reaction-next-starterkit/issues/163)

The Price component needs the ability to render the `compareAtPrice` above the `displayPrice`.
![screen shot 2018-06-26 at 12 37 14 pm](https://user-images.githubusercontent.com/1135948/41929524-f055aa00-793d-11e8-9c19-65cc630e26ad.png)
![screen shot 2018-06-26 at 12 37 08 pm](https://user-images.githubusercontent.com/1135948/41929525-f0745c20-793d-11e8-8b6a-1287b9edf8f0.png)

I think this should just be a simple boolean prop something like `hasPriceBelow` to render the `displayPrice` below the `comparAtPrice`.

### Additional contract requirements

The Price component must accept a boolean `hasPriceBottom` option. When it is true and a compare-at price is present, the compare-at price must render before the display price; with the option omitted, the existing display-price-before-compare-at order remains.
