// Renders SVGs to PNGs with resvg (the renderer the brand assets use).
// stdin: a JSON list of {svg, out}; each SVG carries its own pixel size.
import { Resvg } from '@resvg/resvg-js';
import fs from 'fs';
const jobs = JSON.parse(fs.readFileSync(0, 'utf8'));
for (const { svg, out } of jobs) {
  fs.writeFileSync(out, new Resvg(svg, { font: { loadSystemFonts: false } }).render().asPng());
}
