---
name: diagrams
description: Show the user a diagram, screenshot or any image: render SVG or HTML to a PNG with the image's headless Chromium and give its absolute path, or write Mermaid for a README. Use when asked for a diagram, a visual, screenshots, "show me" or "not text".
---

# Showing images

## Delivering a PNG

- `SendUserFile` fails in a plain session here with "this session is not on a project thread".
- Save the PNG under `~/workspace/shots/` and give its complete absolute path in the reply
  (`/var/home/<you>/workspace/shots/<name>.png`; `~` and relative paths do not link). The client turns the path into a preview link.
- The agent cannot see the user's screen. Say which path was given, not that it opened.
- `Read` on a PNG shows it to the agent only. Images wider than 2000 px are shown downscaled (2640x1640 is shown as 2000x1242).

## Rendering SVG or HTML to a PNG

1. Write the SVG, by hand or from a small Python script (a 1320x800 canvas fits most diagrams), inside an HTML file under `~/workspace/shots/`:
   `<!doctype html><meta charset="utf-8"><body style="margin:0;background:#fff"><svg …/></body>`.
2. Render it (the dbus errors it prints are harmless):
   `chromium-browser --headless --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --screenshot=<abs png path> --window-size=1320,800 file://<abs html path>`
   The PNG is the window size times the scale factor (1320x800 at 2 gives 2640x1600).
3. Open the PNG with `Read` and check for overlaps, clipped labels and arrows through boxes.

SVG skeleton (a box, a text, an arrow with a head):

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1320" height="800" viewBox="0 0 1320 800">
  <defs><marker id="a" markerUnits="userSpaceOnUse" markerWidth="14" markerHeight="14" refX="12" refY="7" orient="auto"><path d="M0 0 L14 7 L0 14 z" fill="#15803d"/></marker></defs>
  <rect x="30" y="110" width="230" height="150" rx="14" fill="#eef2ff" stroke="#1d4ed8" stroke-width="2"/>
  <text x="145" y="170" font-size="20" font-weight="600" text-anchor="middle" font-family="Helvetica, Arial, sans-serif">Agent</text>
  <line x1="260" y1="190" x2="346" y2="184" stroke="#15803d" stroke-width="3" marker-end="url(#a)"/>
</svg>
```

Drawing facts:

- Arrowhead markers scale with the stroke width unless `markerUnits="userSpaceOnUse"` is set.
- A 16 px label needs about 9 px per character: a 290 px box holds about 30 characters.
- Keep the title strip free of boxes, and put badges beside a label, not over it.
- For several designs to compare: same layout and colours in each, short labels, numbered steps with a legend, green for allowed and red dashed for refused.

## Several screenshots on one sheet

- An HTML page with `<img src="file://<abs png path>" style="width:285px">` in a flex row, each with a `<figcaption>`, renders with the command above
  (1320x820 window fits four phone screenshots). The `file://` images load.
- Pillow is installed for Python (`from PIL import Image`) and also pastes images side by side.

## Screenshots of a web page

- Playwright is in `/usr/lib/node_modules`: run `NODE_PATH=/usr/lib/node_modules node script.js`, and launch with
  `chromium.launch({ executablePath: '/usr/bin/chromium-browser', args: ['--no-sandbox'] })`. Do not run `playwright install`.
- A phone: `browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true })`.
  `page.touchscreen.tap(x, y)` taps. `document.documentElement.scrollWidth` greater than the viewport width means the page scrolls sideways.
- Dark mode: `colorScheme: 'dark'` in the context options.
- A page that imports modules from a CDN hangs on `page.goto` (30 s timeout) in the sandbox. Answer those requests from local files
  with `page.route('https://cdn.example/**', r => r.fulfill({ path, contentType: 'text/javascript' }))`.
  Mock the page's API with `page.route('**/api/**', r => r.fulfill({ json }))`.
- `page.screenshot({ path, fullPage: true })` captures the whole page.
- A `pageerror` handler (`page.on('pageerror', e => console.log(e.message))`) shows script errors that otherwise leave the page blank.

## Mermaid in a README

- GitHub renders a fenced `mermaid` block. The existing diagrams in `docs/claude-vm/README.md` use `flowchart`, `<br/>` in labels and short labels.
- Mermaid chooses the layout itself, so the order of the nodes differs from a sketch.
- Check the syntax before pushing: in a scratch directory run `npm install mermaid@11` (outside the sandbox if it cannot reach the registry),
  write a page with `<pre class="mermaid">…</pre>` and
  `<script src="node_modules/mermaid/dist/mermaid.min.js"></script><script>mermaid.initialize({startOnLoad:true})</script>`,
  render it with the command above plus `--virtual-time-budget=8000`, and look at the PNG.
