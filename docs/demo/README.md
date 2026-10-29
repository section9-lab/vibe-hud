# README animation scenery

The demo retains the original 30-second timeline from commit
`4308a53449a0adecf87c4c47f54b4a37ce5e2989`. Its four agents, activity rings,
counts, guide cards, terminal log, pointer, session list, history, and settings
retain the original frame timing and geometry. No new camera movement or workflow
is introduced.

Only the desktop scenery changes: the MacBook frame, wallpaper, terminal window
chrome, and Dock reuse the `www` website's components and assets. The result is
rendered at 2× and cropped to the computer's 2416 × 1536 frame, with transparent outer corners.
There is no surrounding black canvas or caption strip.

The scenery is captured at native 2× resolution. `text.json` supplies the original
UI strings and their baseline positions; `typography.py` redraws matching text
from fonts at the export resolution. Occluded text, fades, rings, icons, and the
pointer retain the original pixels and timing. The GIF palette reserves a neutral
ramp for small text, and frames are streamed as deltas to limit export memory.

Regenerate the GIF with an existing Python environment providing Pillow and NumPy:

```sh
python3 docs/demo/restyle.py
```

The original animation is read from Git history and the included `desktop.png`
provides the scenery. Use `--original /path/to/original.gif` if working from a
shallow checkout without the baseline commit.
Export defaults to macOS SF and Menlo fonts; `--sans-font` and `--mono-font`
can select equivalent font files. No native app dependencies are added.

To update the scenery from the website:

```sh
node docs/demo/preview.mjs ../www
```

This makes an isolated temporary copy and reuses the website's installed
dependencies. It does not edit the website or add native app dependencies.
Open `http://localhost:4322/readme-demo/`, wait for it to load, and save a
full-page **2560 × 1760** PNG as `docs/demo/desktop.png`. The export stylesheet
renders components at 2×; do not enlarge a smaller screenshot afterward.
The fixed logical layout coordinates align with the original animation.

Review representative frames before encoding:

```sh
python3 docs/demo/restyle.py --preview /tmp/vibehud-demo-review
```

Keep the README's sample-session caption. This is a simulated desktop,
not a recording of native app behavior.
