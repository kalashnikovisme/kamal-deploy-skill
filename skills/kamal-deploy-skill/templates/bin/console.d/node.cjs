#!/usr/bin/env node
// bin/console.d/node.cjs - application-aware Node.js REPL (Rails-console equivalent).
//
// Plain CommonJS on purpose: a .cjs file loads the same way in CommonJS and
// "type": "module" projects, needs no build step and no dev dependency.
// Application code is reached through dynamic import()/require(), so ESM and CJS
// both work. It only uses what exists in the CURRENT environment (production
// images included): compiled output (dist/, build/) and node_modules actually present.
//
// Context strategy, first match wins (never starts an HTTP listener, runs no
// migrations, workers or cron):
//   1. console.config.{cjs,mjs,js} (project-owned override, see below)
//   2. NestJS  -> NestFactory.createApplicationContext(AppModule)  => app, get()
//   3. Prisma  -> `prisma` / `db` (lazy; connects on first query)
//   4. otherwise a plain REPL with load()/require()/import() and the env loaded
//
// console.config contract (optional):  module.exports = async ({ root, load }) =>
//   ({ context: { db, services, ... }, close: async () => {}, banner: 'text' })

'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const repl = require('repl');
const { pathToFileURL } = require('url');
const { createRequire } = require('module');

const root = process.cwd();
const req = createRequire(path.join(root, 'noop.js'));
const closers = [];
const notes = [];

function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } }
function exists(...p) { return fs.existsSync(path.join(root, ...p)); }
function resolveOpt(spec) { try { return req.resolve(spec); } catch { return null; } }

async function load(spec) {
  // Relative/absolute file -> import by URL (works for ESM and CJS); bare -> from the project's node_modules.
  const target = spec.startsWith('.') || path.isAbsolute(spec)
    ? pathToFileURL(path.resolve(root, spec)).href
    : pathToFileURL(req.resolve(spec)).href;
  return import(target);
}

function loadEnv() {
  // Local convenience only: existing process env (the container's real env) always wins.
  for (const f of ['.env', '.env.local']) {
    const p = path.join(root, f);
    if (fs.existsSync(p) && typeof process.loadEnvFile === 'function') {
      try { process.loadEnvFile(p); } catch (e) { notes.push(`could not read ${f}: ${e.message}`); }
    }
  }
}

function firstExisting(cands) { return cands.find((c) => exists(c)); }

async function nestContext(pkg) {
  const nestCore = resolveOpt('@nestjs/core');
  if (!nestCore) return null;
  const nestJson = readJson(path.join(root, 'nest-cli.json')) || {};
  const outDir = (readJson(path.join(root, 'tsconfig.build.json')) || readJson(path.join(root, 'tsconfig.json')) || {})
    .compilerOptions?.outDir?.replace(/^\.\//, '') || 'dist';
  const sourceRoot = (nestJson.sourceRoot || 'src').replace(/^\.\//, '');
  const file = firstExisting([
    `${outDir}/app.module.js`, `${outDir}/${sourceRoot}/app.module.js`, `${outDir}/src/app.module.js`,
    'src/app.module.js',
  ]);
  if (!file) {
    notes.push(`NestJS detected but no compiled app.module.js under ${outDir}/ - run the build first (the console targets compiled output; decorators/DI metadata need tsc, not a transpile-only runner).`);
    return null;
  }
  const mod = await load('./' + file);
  const AppModule = mod.AppModule || mod.default?.AppModule || Object.values(mod).find((v) => typeof v === 'function' && /Module$/.test(v.name));
  if (!AppModule) { notes.push(`NestJS: no AppModule export in ${file}`); return null; }
  const { NestFactory } = await import(pathToFileURL(nestCore).href).then((m) => m.NestFactory ? m : m.default);
  const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn'] });
  closers.push(() => app.close());
  const get = (token) => app.get(token, { strict: false });
  return { context: { app, get }, label: 'NestJS application context (no HTTP listener)' };
}

function prismaContext() {
  const p = resolveOpt('@prisma/client');
  if (!p) return null;
  try {
    const { PrismaClient } = req('@prisma/client');
    const prisma = new PrismaClient();   // lazy: no connection until the first query
    closers.push(() => prisma.$disconnect());
    return { context: { prisma, db: prisma }, label: 'Prisma' };
  } catch (e) {
    notes.push(`Prisma present but client unavailable (${e.message.split('\n')[0]}) - run \`prisma generate\`.`);
    return null;
  }
}

async function main() {
  const pkg = readJson(path.join(root, 'package.json')) || {};
  loadEnv();
  const ctx = { load, root };
  const labels = [];

  const cfgFile = firstExisting(['console.config.cjs', 'console.config.mjs', 'console.config.js']);
  let banner = null;
  if (cfgFile) {
    const m = await load('./' + cfgFile);
    const fn = m.default?.default || m.default || m;
    const out = await (typeof fn === 'function' ? fn({ root, load }) : fn);
    Object.assign(ctx, out.context || {});
    if (out.close) closers.push(out.close);
    banner = out.banner || null;
    labels.push(cfgFile);
  } else {
    const nest = await nestContext(pkg);
    if (nest) { Object.assign(ctx, nest.context); labels.push(nest.label); }
    else {
      const pr = prismaContext();
      if (pr) { Object.assign(ctx, pr.context); labels.push(pr.label); }
    }
  }

  const env = process.env.NODE_ENV || 'development';
  const exposed = Object.keys(ctx).filter((k) => !['load', 'root'].includes(k));
  const out = process.stdout;
  out.write(`${pkg.name || path.basename(root)} console (${env}, node ${process.version})\n`);
  if (labels.length) out.write(`  context: ${labels.join(', ')}\n`);
  out.write(`  available: ${['load(spec)', 'require', 'await import(...)', ...exposed].join(', ')}\n`);
  if (banner) out.write(`  ${banner}\n`);
  for (const n of notes) out.write(`  note: ${n}\n`);

  const r = repl.start({ prompt: `${pkg.name || 'app'}(${env})> `, useGlobal: false });
  Object.assign(r.context, ctx, { exit: () => r.close() });
  if (process.stdin.isTTY && !process.env.CONSOLE_NO_HISTORY) {
    try { r.setupHistory(path.join(os.tmpdir(), `.${(pkg.name || 'app').replace(/\W+/g, '_')}_console_history`), () => {}); } catch { /* history is optional */ }
  }

  let closing = false;
  r.on('exit', async () => {
    if (closing) return; closing = true;
    for (const c of closers.reverse()) { try { await c(); } catch { /* best effort cleanup */ } }
    process.exit(0);
  });
}

main().catch((e) => { console.error(`console: failed to initialise the application: ${e && e.stack || e}`); process.exit(1); });
