# CLAUDE.md

FiveM resource `cyphercity-hookah` ("The Sheikh's Place" hookah lounge). The in-game UI (NUI) is plain HTML/CSS/JS in `cyphercity-hookah/html/`, Hebrew RTL first.

## UI work: use the `ui-ux-pro-max` skill

For any change to how the NUI looks, reads or is interacted with, use the project skill in `.claude/skills/ui-ux-pro-max/` (from [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill), MIT). Run its search from the repository root, one concern per query:

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "focus visible keyboard" --domain ux
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "real-time dashboard" --domain chart
```

Project constraints that win over the skill's suggestions:

- The NUI loads nothing from the internet (`tests/static_checks.js` enforces it): no Google Fonts or CDNs. Fonts are bundled (Heebo, Frank Ruhl Libre), both of which cover Hebrew.
- Keep the dark + gold tokens in `html/style.css` `:root`. Secondary text (`--faint`) must stay at 4.5:1 or more on `--panel-4`.
- Every UI string goes in both `he` and `en` in `html/locale.js`, or the static checks fail.
- No framework and no Tailwind, so `--stack` results are general guidance only.
- `--design-system` suggests landing-page layouts and Latin-only fonts, which don't fit an in-game RTL panel. Don't persist its output.

## Tests

```bash
cd cyphercity-hookah && tests/run_all.sh   # needs lua5.4, luacheck, node, Playwright
node tests/nui/nui.test.js ../docs/screenshots   # refresh the README screenshots
```
