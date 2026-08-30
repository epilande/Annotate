# ADR-0002: Single Tool Rendering Authority

Date: 2026-08-30
Status: Accepted

## Decision

`ToolType` owns the conversion from a tool's nominal line width and color to its rendered stroke:

- `strokeWidthMultiplier` is `4.67` for the highlighter and `1` for every other tool.
- `laydownAlpha` is `0.5` for the highlighter and `1` for every other tool.

Rendering, freehand dirty-rect padding, selection tolerance, and eraser hit-testing derive from these properties. They must not repeat the numeric values or maintain a second tool-specific rendering table.

`OverlayView.currentLineWidth` remains the runtime nominal width. A stored `DrawingPath` keeps that nominal width and its unmodified picked color; the active tool properties are applied when the path is rendered or hit-tested.

## Why

The highlighter's effective width and opacity previously appeared as independent constants in drawing and hit-testing code. Those copies could drift, making the visible stroke disagree with interaction bounds or redraw padding. Tool-owned properties keep every consumer on the same values.

## Enforcement

- `ModelTests` fixes the multiplier and alpha contract for every tool.
- `OverlayView` and `OverlayWindow` use the `ToolType` properties at rendering and interaction boundaries.
- Review rejects new inline highlighter width or alpha constants.
