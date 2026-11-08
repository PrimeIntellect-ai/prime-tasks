'Name of a focuable element must not be null' error message from Accessibility Insights on Clipboard example page
Screenshot of Fastpass:

![image](https://github.com/microsoft/react-native-gallery/assets/157416350/3011341d-1b36-42af-81bd-985527e2682e)

Looks like we need to have the accessibilityLabel prop defined on each of these.
'Name of a focuable element must not be null' error message from Accessibility Insights on Lottie example page
Screenshot of Fastpass:

![image](https://github.com/microsoft/react-native-gallery/assets/157416350/99022824-c9d0-4627-a54e-699a9606dafd)

Looks like we need to have the accessibilityLabel prop defined on each of these.
UIA Name and ControlType/LocalizedControlType property errors on Xaml example change.
Screenshot of Fastpass:

![image](https://github.com/user-attachments/assets/69f9fbe7-27f6-4ceb-bfbb-4be7fa30ee30)

All errors are due to the UIA Name and UIA ControlType and LocalizedControlType properties having common text in their values. Will need to change the UIA Name properties (accessibilityLabel) for the impacted components.

### Additional contract requirements

- For the Clipboard example, set the copy control's accessibilityLabel to "Example copy text", the text input's accessibilityLabel to "Example set text to copy", and the paste control's accessibilityLabel to "Example paste text". For the XAML example, set the Button and ComboBox accessibilityLabel values to "Simple example".
