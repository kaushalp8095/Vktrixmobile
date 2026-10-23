require('dotenv').config();
const knex = require('knex');
const client = process.env.DB_CLIENT || 'better-sqlite3';
const url = process.env.DATABASE_URL || '';
// External URL (e.g. *.render.com) ya DB_SSL=true par SSL on
const useSsl = process.env.DB_SSL === 'true' || /\.(render\.com|neon\.tech|supabase\.(co|com))/.test(url);
// `rejectUnauthorized: false` bina certificate verify ke encrypt karta hai — beech
// me baitha attacker DB traffic padh/badal sakta hai. Provider ka CA DB_SSL_CA me
// daalein (PEM, ya \n escapes ke saath) to verification on ho jati hai. Purane
// deployments na tootein isliye bina CA par behavior wahi rehta hai, bas warning.
const sslCa = (process.env.DB_SSL_CA || '').replace(/\\n/g, '\n').trim();
if (useSsl && !sslCa) {
  console.warn('[db] TLS on hai par DB_SSL_CA set nahi — server certificate verify nahi ho raha. '
    + 'Provider ka CA certificate DB_SSL_CA me daalein.');
}
const ssl = useSsl ? (sslCa ? { ca: sslCa, rejectUnauthorized: true } : { rejectUnauthorized: false }) : false;
const db = knex(client === 'pg'
  ? { client: 'pg', connection: { connectionString: url, ssl }, pool: { min: 0, max: 10 } }
  : { client: 'better-sqlite3', connection: { filename: process.env.SQLITE_FILE || './dev.sqlite' }, useNullAsDefault: true });
module.exports = db;
