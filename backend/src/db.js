require('dotenv').config();
const knex = require('knex');
const client = process.env.DB_CLIENT || 'better-sqlite3';
const url = process.env.DATABASE_URL || '';
// External URL (e.g. *.render.com) ya DB_SSL=true par SSL on
const useSsl = process.env.DB_SSL === 'true' || /\.(render\.com|neon\.tech|supabase\.co)/.test(url);
const db = knex(client === 'pg'
  ? { client: 'pg', connection: { connectionString: url, ssl: useSsl ? { rejectUnauthorized: false } : false }, pool: { min: 0, max: 10 } }
  : { client: 'better-sqlite3', connection: { filename: process.env.SQLITE_FILE || './dev.sqlite' }, useNullAsDefault: true });
module.exports = db;
