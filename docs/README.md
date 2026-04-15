# Documentation

This directory contains project documentation, guides, and supporting materials.

## Structure

```
docs/
├── README.md      # This file
├── figs/          # Images and figures used in documentation
```

## Adding Images

Save your images in the `figs/` directory. To embed them in a Markdown file with
controlled sizing, use an HTML `<img>` tag instead of Markdown's `![]()` syntax.
This gives you fine-grained control over the rendered width:

```html
<img src="docs/figs/architecture-diagram.png" width="600" alt="Architecture Diagram">
```

When referencing images from this `docs/README.md` file (i.e., from within `docs/`),
use a relative path:

```html
<img src="figs/architecture-diagram.png" width="600" alt="Architecture Diagram">
```

### Tips

- **Width only:** Setting just `width` preserves the aspect ratio automatically. No
  need to also set `height`.
- **Percentage widths:** You can use `width="80%"` to make images responsive to the
  container width.
- **Centering:** Wrap the `<img>` tag in a `<p>` or `<div>` with `align="center"`:

  ```html
  <p align="center">
    <img src="docs/figs/demo.png" width="500" alt="Demo screenshot">
  </p>
  ```
