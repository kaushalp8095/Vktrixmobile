// Production defaults: dev secret / default admin password kabhi production me na chalein.
//
// Bug 1: `JWT_SECRET` missing ho to secret `'dev_secret'` ban jata tha — repo
//        padhne wala koi bhi super-admin token bana sakta tha.
// Bug 2: `SUPERADMIN_PASSWORD` missing ho to super admin `Admin@123` ke saath seed
//        hota tha (Render par ye var optional hai).
const test = require('node:test');
const assert = require('node:assert');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const root = path.join(__dirname, '..');

/** Child process me ek snippet chalata hai — module-level env guards test karne ke liye. */
function run(code, env) {
  return spawnSync(process.execPath, ['-e', code], {
    cwd: root,
    env: { ...process.env, ...env },
    encoding: 'utf8',
    timeout: 30000,
  });
}

test('production refuses to start without JWT_SECRET', () => {
  const r = run("require('./src/auth')", { NODE_ENV: 'production', JWT_SECRET: '' });
  assert.notStrictEqual(r.status, 0, 'auth module should throw without JWT_SECRET in production');
  assert.match(`${r.stderr}`, /JWT_SECRET is required in production/);
});

test('production starts with a real JWT_SECRET', () => {
  const r = run("require('./src/auth'); console.log('loaded')", { NODE_ENV: 'production', JWT_SECRET: 'a-real-secret-value' });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.match(r.stdout, /loaded/);
});

test('tests/dev keep the fallback secret (existing test suites unaffected)', () => {
  const r = run("require('./src/auth'); console.log('loaded')", { NODE_ENV: 'test', JWT_SECRET: '' });
  assert.strictEqual(r.status, 0, r.stderr);
});

test('production refuses to seed a super admin with the default password', async () => {
  const file = path.join(root, 'dev-missing-superadmin.sqlite');
  const r = run(
    "const migrate = require('./src/migrate'); migrate()" +
      ".then(() => { console.log('MIGRATED'); process.exit(0); })" +
      ".catch(e => { console.error(e.message); process.exit(3); })",
    {
      NODE_ENV: 'production',
      JWT_SECRET: 'prod-secret',
      SUPERADMIN_PASSWORD: '',
      DB_CLIENT: 'better-sqlite3',
      SQLITE_FILE: file,
      DATABASE_URL: '',
    },
  );
  try {
    assert.strictEqual(r.status, 3, `migrate should fail: ${r.stdout}${r.stderr}`);
    assert.match(`${r.stderr}`, /SUPERADMIN_PASSWORD is required/);
  } finally {
    require('node:fs').rmSync(file, { force: true });
  }
});

test('outside production a missing super admin password is generated, not defaulted', () => {
  const file = path.join(root, 'dev-random-superadmin.sqlite');
  const r = run(
    "const migrate = require('./src/migrate'); migrate()" +
      ".then(() => { console.log('MIGRATED'); process.exit(0); })" +
      ".catch(e => { console.error(e.message); process.exit(3); })",
    {
      NODE_ENV: 'test',
      SUPERADMIN_PASSWORD: '',
      DB_CLIENT: 'better-sqlite3',
      SQLITE_FILE: file,
      DATABASE_URL: '',
    },
  );
  try {
    assert.strictEqual(r.status, 0, `${r.stdout}${r.stderr}`);
    assert.match(r.stdout, /temporary password:/);
    assert.doesNotMatch(r.stdout, /Admin@123/);
  } finally {
    require('node:fs').rmSync(file, { force: true });
  }
});
