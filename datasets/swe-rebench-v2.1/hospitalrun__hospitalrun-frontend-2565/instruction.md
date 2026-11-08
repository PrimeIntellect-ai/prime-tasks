Focus of menu item "Visits" disappears when I view the details
## 🐛 Bug Report

A clear and concise description of what the bug is.

## To Reproduce

When I view a visit detail tab, the focus of the "Visits" menu item disappears preventing me from understanding in which section I'm in.

Right behavior

<img width="1570" alt="Screenshot 2021-02-09 at 12 38 19" src="https://user-images.githubusercontent.com/6388707/107358559-d3439f00-6ad3-11eb-9248-0cdc9fb7a622.png">

Wrong behavior

<img width="1558" alt="Screenshot 2021-02-09 at 12 38 25" src="https://user-images.githubusercontent.com/6388707/107358566-d63e8f80-6ad3-11eb-8569-f561a5e64739.png">

### Additional contract requirements

- The "Visits" tab must remain active (keep the `active` state) for any route that starts with `/patients/:id/visits`, including nested routes such as a visit detail view, not only for the exact `/patients/:id/visits` path.
