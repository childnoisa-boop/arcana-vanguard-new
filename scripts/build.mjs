import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dist = path.join(root, 'dist');
await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });

for (const name of ['index.html', 'cloud.js', '_redirects', '_headers', 'manus-routes.json']) {
  try {
    await cp(path.join(root, name), path.join(dist, name));
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    if (name === 'cloud.js') throw new Error(`Missing required app file: ${name}`);
  }
}

const config = {
  supabaseUrl: process.env.SUPABASE_URL || '',
  supabaseAnonKey: process.env.SUPABASE_ANON_KEY || '',
};
await writeFile(
  path.join(dist, 'config.js'),
  `window.CARD_APP_CONFIG = Object.freeze(${JSON.stringify(config)});\n`,
  'utf8',
);

try {
  await cp(path.join(root, 'assets'), path.join(dist, 'assets'), { recursive: true });
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

const missing = Object.entries(config).filter(([, value]) => !value).map(([key]) => key);
if (missing.length) console.warn(`Build succeeded in preview mode; Netlify environment variables still needed: ${missing.join(', ')}`);
console.log(`Static app built at ${dist}`);
