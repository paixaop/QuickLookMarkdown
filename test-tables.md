# Table Rendering Test

## Simple Table

| Name    | Age | City       |
|---------|-----|------------|
| Alice   | 30  | New York   |
| Bob     | 25  | London     |
| Charlie | 35  | Tokyo      |

## Aligned Columns

| Left-aligned | Center-aligned | Right-aligned |
|:-------------|:--------------:|--------------:|
| Left         | Center         |         Right |
| `code`       | **bold**       |        *italic* |
| foo          | bar            |           baz |

## Wide Table

| Feature       | Status | Notes                          | Priority |
|---------------|--------|--------------------------------|----------|
| Tables        | Done   | Using swift-markdown + cmark-gfm | High   |
| Mermaid       | Done   | Via mermaid.min.js             | Medium   |
| Syntax HL     | Done   | Via highlight.js               | Medium   |
| Dark mode     | Done   | CSS media query                | Low      |

## Mixed Content

Some text before the table.

| Markdown      | Renders as        |
|---------------|-------------------|
| `inline code` | inline code       |
| **bold**      | bold text         |
| *italic*      | italic text       |
| [link](https://example.com) | a hyperlink |

Some text after the table.
