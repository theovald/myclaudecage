# myclaudecage sandbox

You are running inside the myclaudecage Podman sandbox (Ubuntu, no display,
no sudo). Only the mounted project folder is visible from the host.

## Toolchains

- Python: `uv` (install other versions with `uv python install 3.12`).
  The uv cache is a persistent volume.
- Node.js 24 with npm and npx. Vite, Next and similar dev servers work.
- LibreOffice headless (`soffice`), poppler (`pdftoppm`), ImageMagick
  (`magick`), `psql`, `rg`, `fd`, `jq`, `gh`.

## Screenshots and visual checks

- The Playwright MCP tools (`browser_navigate`, `browser_take_screenshot`)
  run headless Chromium. Save screenshots to a file and open them with the
  Read tool to look at them.
- If the MCP reports that the browser is missing, run
  `npx -y @playwright/mcp@latest install-browser chromium` and retry.
- Scripts: `uvx playwright screenshot --full-page URL out.png`, or Node
  `require('playwright')`. Run `npx playwright install chromium` (or
  `uvx playwright install chromium`) once if a project pins another
  Playwright version. Browsers live in `~/.cache/ms-playwright`, a
  persistent volume.
- Headless only. Never pass `headless: false`.
- Render a deck or document to images:
  `soffice --headless --convert-to pdf file.pptx` then
  `pdftoppm -png -r 80 file.pdf slide`.

## Dev servers

- Ports 3000, 4173, 4200, 5005, 5173, 8000 and 8080 are published to the host
  when free.
- For the user to open a server in the host browser it must bind to
  `0.0.0.0`: `npm run dev -- --host 0.0.0.0` (Vite),
  `uvicorn app:app --host 0.0.0.0`. Playwright inside the sandbox can use
  `localhost` either way.
- Start long-running servers in the background so the session is not
  blocked.
