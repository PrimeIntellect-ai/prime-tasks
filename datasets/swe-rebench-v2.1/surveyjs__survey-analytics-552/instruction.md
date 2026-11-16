An exception is raised when you enable the Chart visualizer for a specialized question based on a Dropdown
T23638 - Dashboard Visualizer for Custom (Specialized) Question Types
https://surveyjs.answerdesk.io/internal/ticket/details/T23638
***
[View Demo](https://codesandbox.io/p/devbox/vigorous-cerf-f93wp6?workspaceId=ws_QrfppueirPWWh9z2ztBr8j)

Refer to the `m1` question: it is visualized by a Text visualizer, however, if you select Chart, the following exception is thrown:
```
Uncaught (in promise) TypeError: Cannot read properties of undefined (reading 'map')
    at SelectBasePlotly.getValues (survey.analytics.mjs:1470:39)
    at defaultStatisticsCalculator (survey.analytics.mjs:879:27)
    at SelectBasePlotly.getCalculatedValuesCore (survey.analytics.mjs:802:12)
    at SelectBasePlotly.getCalculatedValuesCore (survey.analytics.mjs:6611:30)
    at eval (survey.analytics.mjs:841:40)
    at new Promise (<anonymous>)
    at SelectBasePlotly.getCalculatedValues (survey.analytics.mjs:811:12)
    at SelectBasePlotly.eval (survey.analytics.mjs:1549:33)
    at Generator.next (<anonymous>)
    at eval (survey.analytics.mjs:426:67)
    at new Promise (<anonymous>)
    at __awaiter (survey.analytics.mjs:408:10)
    at SelectBasePlotly.getAnswersData (survey.analytics.mjs:1547:12)
    at PlotlyChartAdapter.eval (survey.analytics.mjs:6534:44)
    at Generator.next (<anonymous>)
    at eval (survey.analytics.mjs:426:67)
    at new Promise (<anonymous>)
    at __awaiter (survey.analytics.mjs:408:10)
    at PlotlyChartAdapter.update (survey.analytics.mjs:6533:12)
    at PlotlyChartAdapter.eval (survey.analytics.mjs:6497:48)
    at Generator.next (<anonymous>)
    at eval (survey.analytics.mjs:426:67)
    at new Promise (<anonymous>)
    at __awaiter (survey.analytics.mjs:408:10)
    at PlotlyChartAdapter.create (survey.analytics.mjs:6496:12)
    at SelectBasePlotly.eval (survey.analytics.mjs:6599:32)
    at Generator.next (<anonymous>)
    at eval (survey.analytics.mjs:426:67)
    at new Promise (<anonymous>)
    at __awaiter (survey.analytics.mjs:408:10)
    at SelectBasePlotly.renderContentAsync (survey.analytics.mjs:6595:12)
    at SelectBasePlotly.renderContent (survey.analytics.mjs:674:12)
    at SelectBasePlotly.render (survey.analytics.mjs:719:10)
    at AlternativeVisualizersWrapper.renderContent (survey.analytics.mjs:2030:21)
    at AlternativeVisualizersWrapper.updateContent (survey.analytics.mjs:726:10)
    at eval (survey.analytics.mjs:738:14)Understand this error
```

### Additional contract requirements

- A specialized (custom/composite) question based on a Dropdown exposes its `choices` through the inherited composite props. A SelectBase-derived visualizer registered for such a question type (for example, the Chart visualizer) must use those choices when computing its values and labels, and must not throw when computing its answers data.


- For a composite Dropdown question with choices `FRA`/`France`, `ATG`/`Antigua and Barbuda`, and `ALB`/`Albania`, `getValues()` must return `["ALB", "ATG", "FRA"]` and `getLabels()` must return `["Albania", "Antigua and Barbuda", "France"]`.
