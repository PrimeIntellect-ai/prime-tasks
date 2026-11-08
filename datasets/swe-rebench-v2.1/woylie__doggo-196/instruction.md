aria-invalid and aria-errormessage
Update `input` component to set `aria-invalid` and `aria-errormessage` attributes. Maybe use a live region for validation errors as well.

- https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Attributes/aria-invalid
- https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Attributes/aria-errormessage
- https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/ARIA_Live_Regions

### Additional contract requirements

- When an input has both errors and a description, `aria-describedby` must contain only the description ID; in the tested case, its value is `species_description`.
- When an input has no errors, omit both `aria-invalid` and `aria-errormessage` attributes.
