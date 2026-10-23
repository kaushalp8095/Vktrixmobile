// Rate limiter ka contract — brute-force protection isi par khadi hai.
const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { hit, reset, resetAll } = require('../src/ratelimit');

beforeEach(() => resetAll());

test('a key is allowed max times per window, then limited', () => {
  const opts = { name: 'unit', key: 'ip-1', windowMs: 1000, max: 3 };
  assert.equal(hit({ ...opts, at: 0 }).limited, false);
  assert.equal(hit({ ...opts, at: 10 }).limited, false);
  assert.equal(hit({ ...opts, at: 20 }).limited, false);
  const blocked = hit({ ...opts, at: 30 });
  assert.equal(blocked.limited, true);
  assert.equal(blocked.count, 4);
  assert.equal(blocked.retryAfter, 1, 'retry-after seconds me hota hai');
});

test('keys are isolated and the window resets', () => {
  const base = { name: 'unit-2', windowMs: 1000, max: 1 };
  assert.equal(hit({ ...base, key: 'a', at: 0 }).limited, false);
  assert.equal(hit({ ...base, key: 'a', at: 1 }).limited, true);
  assert.equal(hit({ ...base, key: 'b', at: 2 }).limited, false, 'dusra key apna alag counter rakhta hai');
  assert.equal(hit({ ...base, key: 'a', at: 1001 }).limited, false, 'window ke baad phir se allowed');
});

test('reset clears one key only (successful login forgives failures)', () => {
  const base = { name: 'unit-3', windowMs: 60_000, max: 2 };
  hit({ ...base, key: 'krishna', at: 0 });
  hit({ ...base, key: 'krishna', at: 0 });
  assert.equal(hit({ ...base, key: 'krishna', at: 0 }).limited, true);
  reset({ name: 'unit-3', key: 'krishna' });
  assert.equal(hit({ ...base, key: 'krishna', at: 0 }).limited, false);
});

test('missing keys never crash and fall into one bucket', () => {
  const base = { name: 'unit-4', windowMs: 1000, max: 1 };
  assert.equal(hit({ ...base, key: undefined, at: 0 }).limited, false);
  assert.equal(hit({ ...base, key: null, at: 0 }).limited, true);
});
