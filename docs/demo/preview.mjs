import { cp, mkdtemp, readFile, symlink, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawn } from 'node:child_process'

// Use an isolated copy of www and its installed dependencies, without edits.
const source = dirname(fileURLToPath(import.meta.url))
const website = resolve(process.argv[2] ?? join(source, '../../../www'))
const stage = await mkdtemp(join(tmpdir(), 'vibehud-desktop-'))
for (const name of ['src', 'public', 'package.json', 'astro.config.ts', 'tailwind.config.ts', 'tsconfig.json', 'eslint.config.mjs']) {
  await cp(join(website, name), join(stage, name), { recursive: true })
}
await symlink(join(website, 'node_modules'), join(stage, 'node_modules'))
const originalConfig = await readFile(join(stage, 'astro.config.ts'), 'utf8')
await writeFile(join(stage, 'astro.config.ts'), originalConfig
  .replace('export default defineConfig({', 'export default defineConfig({\n  devToolbar: { enabled: false },')
  .replace('vite: {', `vite: {\n    server: { fs: { allow: ${JSON.stringify([stage, website])} } },`))
await cp(join(source, 'ReadmeDesktop.tsx'), join(stage, 'src/components/ReadmeDesktop.tsx'))
await cp(join(source, 'styles.css'), join(stage, 'src/assets/css/readme-desktop.css'))
await writeFile(join(stage, 'src/pages/readme-demo.astro'), `---
import ReadmeDesktop from '../components/ReadmeDesktop'
import '../assets/css/main.css'
import '../assets/css/readme-desktop.css'
---
<!doctype html><html lang="en"><head><meta charset="utf-8" /><meta name="viewport" content="width=device-width" /><title>vibe hud desktop scenery</title></head><body><ReadmeDesktop client:load /></body></html>
`)
console.log(`Preview source: ${stage}\nCapture http://localhost:4322/readme-demo/ as a full-page 2560 × 1760 screenshot (2× native render).`)
const astro = JSON.parse(await readFile(join(website, 'node_modules/astro/package.json'), 'utf8'))
const child = spawn(process.execPath, [join(website, 'node_modules/astro', astro.bin.astro), 'dev', '--root', stage, '--host', '127.0.0.1', '--port', '4322'], { stdio: 'inherit' })
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal))
child.on('exit', (code) => process.exit(code ?? 0))
