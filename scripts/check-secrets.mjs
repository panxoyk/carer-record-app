#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const patterns = [
  /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/,
  /sb_secret_[A-Za-z0-9_-]{12,}/,
  /SUPABASE_SERVICE_ROLE_KEY\s*=\s*[^$\s"'][^\s"']*/,
];

try {
  const names = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'])
    .toString('utf8')
    .split('\0')
    .filter(Boolean);
  let found = false;
  let readFailed = false;

  for (const name of names) {
    try {
      const content = readFileSync(name);
      if (content.includes(0)) continue;
      const text = content.toString('utf8');
      if (patterns.some((pattern) => pattern.test(text))) found = true;
    } catch (error) {
      if (error.code !== 'ENOENT' && error.code !== 'EISDIR') readFailed = true;
    }
  }

  if (found) {
    console.log('FAIL secret/JWT candidate detected in repository files');
    process.exitCode = 1;
  } else if (readFailed) {
    console.error('FAIL secret scan could not read repository files');
    process.exitCode = 1;
  } else {
    console.log('PASS no literal service key/JWT candidates in repository files');
  }
} catch {
  console.error('FAIL secret scan could not enumerate repository files');
  process.exitCode = 1;
}
