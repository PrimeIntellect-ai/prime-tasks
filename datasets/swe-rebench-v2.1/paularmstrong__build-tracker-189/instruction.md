feat(app): Press on size or delta cell in ComparisonTable to show more information
# Problem

Sometimes when I'm digging into the table, I want to see more information about the artifact in the build or the delta (like all sizeKey changes, etc). There's currently no short way of doing that.

# Solution

On press (click), a modal window could open that nicely formats the full `Artifact` or `ArtifactDelta` object (depending on which cell type).

### Additional contract requirements

- The modal lists every size key of the artifact. In the delta modal, each row shows the size key name and a value formatted as `<formatted size> (<percent change>%)`, where the percent change is rendered with exactly three decimal places. For example, a size of 2400 bytes with a 20% change is shown as `2.34 KiB (20.000%)`, and a size of 4300 bytes with a 50% change is shown as `4.2 KiB (50.000%)`.
- The modal is exposed with an accessibility role of `dialog`, and its close button has the accessible label `Close`.


- In the artifact modal, format size values using the same byte formatting as the cell; for example, 2400 bytes is shown as `2.34 KiB` and 4300 bytes as `4.2 KiB`.
