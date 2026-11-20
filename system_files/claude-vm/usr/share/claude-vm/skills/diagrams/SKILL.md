---
name: diagrams
description: Draw an architecture or flow diagram the user can look at, as a PNG (SVG rendered with the image's headless Chromium) or as Mermaid for a README. Use when asked for a diagram, a visual, or "not text".
---

# Diagrams

## A PNG the user can open

1. Write the diagram as SVG, by hand or from a small Python script (a 1320x800 canvas fits most). Wrap it in an HTML file under
   `~/workspace/shots/`: `<!doctype html><meta charset="utf-8"><body style="margin:0;background:#fff"><svg …/></body>`.
2. Render it with the image's Chromium (the dbus errors it prints are harmless):
   `chromium-browser --headless --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --screenshot=<abs png path> --window-size=1320,800 file://<abs html path>`
3. Open the PNG with Read and fix what you see (overlaps, clipped labels, arrows through boxes), then render again. A first draft always has some.
4. Share it by giving the complete absolute path in the reply (`/var/home/<you>/workspace/shots/<name>.png`, not `~` or a relative path):
   the client turns it into a preview link. `SendUserFile` fails in a plain session here ("not on a project thread"). You cannot see the
   user's screen, so say that the path is what you gave, not that it opened.

SVG skeleton (boxes, a text, an arrow with a head):

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1320" height="800" viewBox="0 0 1320 800">
  <defs><marker id="a" markerUnits="userSpaceOnUse" markerWidth="14" markerHeight="14" refX="12" refY="7" orient="auto"><path d="M0 0 L14 7 L0 14 z" fill="#15803d"/></marker></defs>
  <rect x="30" y="110" width="230" height="150" rx="14" fill="#eef2ff" stroke="#1d4ed8" stroke-width="2"/>
  <text x="145" y="170" font-size="20" font-weight="600" text-anchor="middle" font-family="Helvetica, Arial, sans-serif">Agent</text>
  <line x1="260" y1="190" x2="346" y2="184" stroke="#15803d" stroke-width="3" marker-end="url(#a)"/>
</svg>
```

What went wrong in a first draft, so check for it:

- Arrowheads huge: markers scale with the stroke width unless `markerUnits="userSpaceOnUse"`.
- Text wider than its box: about 9 px per character at 16 px, so a 290 px box holds about 30 characters; shorten the label.
- A box on top of the title, and a badge on top of a label: keep the title strip free and put badges beside the text, not over it.
- Several designs to compare: same layout and colours for each, short labels, numbered steps with a legend, green for allowed and red dashed for refused.

## Mermaid in a README

GitHub renders a fenced `mermaid` block. Follow the existing diagrams in `docs/claude-vm/README.md` (`flowchart`, `<br/>` in labels, short). Mermaid
chooses the layout itself, so the order of the nodes will differ from a sketch. Check the syntax before pushing: in a scratch directory run
`npm install mermaid@11` (outside the sandbox if it cannot reach the registry), write a page with `<pre class="mermaid">…</pre>` and
`<script src="node_modules/mermaid/dist/mermaid.min.js"></script><script>mermaid.initialize({startOnLoad:true})</script>`, render it with the
command above plus `--virtual-time-budget=8000`, and look at the PNG.
