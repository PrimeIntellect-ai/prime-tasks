[Timeline] item.parent === null - "Cannot read property 'top' of null"
Component: Timeline
Version: 4.21.0

The issue doesn't seem to happen often, maybe 1 in 4. But in the below code snippet, the line in red seems to throw due to `group` being null. Is there a race condition somewhere I should be aware about? Am I best off not initializing the timeline until I have events ready to go?

**Example:**
```ts
const timeline = new VisTimeline(
    document.getElementById('my-timeline'),
    [],
    {
        align: 'center',
        maxHeight: '300px',
	    height: '300px',
    	autoResize: true,
	    stackSubgroups: true,
	    zoomable: true,
		showMajorLabels: true,
		showMinorLabels: true,
    }
);

getMyDataFromAHTTPCall()
    .then(arrayOfCompaitbleEvents => {
        timeline.setItems(new DataSet(arrayOfCompaitbleEvents));
    });
```

**Stack:**
```sh
Cannot read property 'top' of null
TypeError: Cannot read property 'top' of null
    at getItemVerticalScroll (node_modules/vis/dist/vis.js:41146:22)
    at Timeout.setFinalVerticalPosition [as _onTimeout] (node_modules/vis/dist/vis.js:41057:33)
```

**Source:**
```diff
function getItemVerticalScroll(timeline, item) {
  var leftHeight = timeline.props.leftContainer.height;
  var contentHeight = timeline.props.left.height;

  var group = item.parent;
- var offset = group.top;
  var shouldScroll = true;
  var orientation = timeline.timeAxis.options.orientation.axis;
```
> dist/vis.js:41146:22
