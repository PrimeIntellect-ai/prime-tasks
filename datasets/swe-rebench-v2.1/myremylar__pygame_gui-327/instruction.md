MessageWindow - variables in translated strings
**Is your feature request related to a problem? Please describe.**
I want to be able to use variables in translated strings, so I could let the user know about things like which file they're about to overwrite.

**Describe the solution you'd like**
The solution described in this discussion would be fine: https://github.com/MyreMylar/pygame_gui/discussions/261

**Additional context**
Labels already support variables, but MessageWindows and other elements don't.

### Additional contract requirements

Elements with text accept a dictionary of string variables that is passed to the translation
engine when a translated string is rendered, so placeholders such as `%{name}` in the translated
text are substituted. The following public API additions provide this:

- `UIButton.__init__` in `pygame_gui/elements/ui_button.py` accepts the keyword-only arguments
  `text_kwargs: Optional[Dict[str, str]] = None` and
  `tool_tip_text_kwargs: Optional[Dict[str, str]] = None`. The button's label and its tooltip are
  rendered from their translated strings with these variables substituted.
- `UIButton.set_text(self, text: str, *, text_kwargs: Optional[Dict[str, str]] = None)` updates the
  label, substituting the supplied variables into the translated string.
- `UILabel.__init__` in `pygame_gui/elements/ui_label.py` accepts the keyword-only argument
  `text_kwargs: Optional[Dict[str, str]] = None`, and
  `UILabel.set_text(self, text: str, *, text_kwargs: Optional[Dict[str, str]] = None)` substitutes
  the supplied variables into the translated label text.
- `UITextBox.__init__` in `pygame_gui/elements/ui_text_box.py` accepts the keyword-only argument
  `text_kwargs: Optional[Dict[str, str]] = None`, and
  `UITextBox.set_text(self, html_text: str, *, text_kwargs: Optional[Dict[str, str]] = None)`
  substitutes the supplied variables into the translated HTML content.
- `UITooltip.__init__` in `pygame_gui/elements/ui_tool_tip.py` accepts the keyword-only argument
  `text_kwargs: Dict[str, str] = None`, substituting the supplied variables into the translated
  tooltip HTML text.
- `UIManager.create_tool_tip` in `pygame_gui/ui_manager.py` accepts the keyword-only argument
  `text_kwargs: Optional[Dict[str, str]] = None` and forwards it so the created tooltip's
  translated text is substituted.
- `UIConfirmationDialog.__init__` in `pygame_gui/windows/ui_confirmation_dialog.py` accepts the
  argument `action_long_desc_text_kwargs: Optional[Dict[str, str]] = None`, substituting the
  supplied variables into the translated long description.
- `UIMessageWindow.__init__` in `pygame_gui/windows/ui_message_window.py` accepts the keyword-only
  argument `html_message_text_kwargs: Optional[Dict[str, str]] = None`, substituting the supplied
  variables into the translated HTML message.
- `UITextEntryLine` in `pygame_gui/elements/ui_text_entry_line.py` displays a translation key
  supplied as its `placeholder_text` as the translated string.
