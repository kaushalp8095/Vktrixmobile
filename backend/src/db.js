require('dotenv').config();
const knex = require('knex');
const client = process.env.DB_CLIENT || 'better-sqlite3';
const db = knex(client === 'pg'
  ? { client: 'pg', connection: process.env.DATABASE_URL, pool: { min: 1, max: 10 } }
  : { client: 'better-sqlite3', connection: { filename: process.env.SQLITE_FILE || './dev.sqlite' }, useNullAsDefault: true });
module.exports = db;
