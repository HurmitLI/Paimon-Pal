#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const runtimeRoot = path.join(
  __dirname,
  '..',
  '..',
  'Tools',
  'LocalModelProbe',
  '.build',
  'arm64-apple-macosx',
  'release'
);
const required = [
  ['notchflow-model-probe', true],
  ['mlx.metallib', false],
];

for (const [name, executable] of required) {
  const filePath = path.join(runtimeRoot, name);
  let stat;
  try {
    stat = fs.statSync(filePath);
    if (!stat.isFile() || stat.size === 0) throw new Error('empty');
    if (executable) fs.accessSync(filePath, fs.constants.X_OK);
  } catch (error) {
    process.stderr.write(`Missing required local AI runtime asset: ${filePath}\n`);
    process.stderr.write('Run ../Tools/LocalModelProbe/build_runtime.sh before packaging.\n');
    process.exit(1);
  }
}

process.stdout.write('Local AI runtime assets are ready.\n');
