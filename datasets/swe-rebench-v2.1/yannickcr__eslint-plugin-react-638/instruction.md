False positive for react/jsx-pascal-case on namespaced components
In v5.2.0 I'm getting a false positive for the `react/jsx-pascal-case` rule when using namespaced components.

```jsx
<Modal show={showModal} onHide={this.closeModal}>
  <Modal.Header closeButton>
    <Modal.Title>Demo</Modal.Title>
  </Modal.Header>
</Modal>
```

It looks like it was introduced in cd5ef2b17257d10f5398c35d7fc73fdfb9a360f9.
