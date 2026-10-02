const db = require('./db');
const bcrypt = require('bcryptjs');

async function migrate() {
  if (!(await db.schema.hasTable('shops'))) {
    await db.schema.createTable('shops', t => {
      t.increments('id');
      t.string('name').notNullable();
      t.string('owner_name'); t.string('phone'); t.string('address'); t.string('gst_no');
      t.boolean('active').defaultTo(true);
      t.timestamp('created_at').defaultTo(db.fn.now());
    });
  }
  if (!(await db.schema.hasTable('users'))) {
    await db.schema.createTable('users', t => {
      t.increments('id');
      t.string('username').notNullable().unique();
      t.string('password_hash').notNullable();
      t.string('name');
      t.string('role').notNullable(); // superadmin | shop_admin | staff
      t.integer('shop_id').references('shops.id').onDelete('CASCADE');
      t.boolean('active').defaultTo(true);
      t.integer('token_version').notNullable().defaultTo(0);
      t.timestamp('created_at').defaultTo(db.fn.now());
    });
  }
  if (!(await db.schema.hasTable('tac_models'))) {
    await db.schema.createTable('tac_models', t => {
      t.string('tac', 8).primary();          // IMEI ke pehle 8 digit
      t.string('brand'); t.string('model');
      t.string('ram'); t.string('storage'); t.string('color');
      t.timestamp('updated_at').defaultTo(db.fn.now());
    });
  }
  if (!(await db.schema.hasTable('phones'))) {
    await db.schema.createTable('phones', t => {
      t.increments('id');
      t.integer('shop_id').notNullable().references('shops.id').onDelete('CASCADE');
      t.string('imei', 15).notNullable();
      t.string('imei2', 15);
      t.string('brand'); t.string('model'); t.string('ram'); t.string('storage'); t.string('color');
      t.string('condition');                 // Excellent / Good / Fair / Faulty
      t.string('accessories');               // box, charger, bill
      t.decimal('buy_price', 12, 2).notNullable();
      t.date('buy_date').notNullable();
      t.string('seller_name'); t.string('seller_phone'); t.string('seller_id_type'); t.string('seller_id_no');
      t.string('seller_address');
      t.text('notes');
      t.string('status').notNullable().defaultTo('in_stock'); // in_stock | sold
      t.integer('created_by').references('users.id');
      t.timestamp('created_at').defaultTo(db.fn.now());
      t.index(['shop_id', 'status']); t.index(['imei']);
    });
  }
  if (!(await db.schema.hasTable('sales'))) {
    await db.schema.createTable('sales', t => {
      t.increments('id');
      t.integer('shop_id').notNullable().references('shops.id').onDelete('CASCADE');
      t.integer('phone_id').notNullable().references('phones.id').onDelete('CASCADE');
      t.decimal('sell_price', 12, 2).notNullable();
      t.decimal('buy_price_at_sale', 12, 2);
      t.date('sell_date').notNullable();
      t.string('customer_name'); t.string('customer_phone'); t.string('customer_address');
      t.string('payment_mode').defaultTo('cash'); // cash | upi | card | credit
      t.string('warranty');
      t.text('notes');
      t.integer('created_by').references('users.id');
      t.timestamp('created_at').defaultTo(db.fn.now());
      t.index(['shop_id', 'sell_date']);
    });
  }

  // Additive, idempotent migrations for existing deployments.
  if (!(await db.schema.hasColumn('users', 'token_version'))) {
    await db.schema.alterTable('users', t => t.integer('token_version').notNullable().defaultTo(0));
  }
  if (!(await db.schema.hasColumn('sales', 'buy_price_at_sale'))) {
    await db.schema.alterTable('sales', t => t.decimal('buy_price_at_sale', 12, 2));
  }
  // Old sale rows predate cost snapshots. Backfill the best available current
  // phone cost; historical edits already made cannot be reconstructed.
  await db.raw('UPDATE sales SET buy_price_at_sale = (SELECT phones.buy_price FROM phones WHERE phones.id = sales.phone_id) WHERE buy_price_at_sale IS NULL');

  // Fail safely (without dropping/changing sale data) if old race bugs already
  // created multiple active sale rows for one phone. Resolve these before deploy.
  const duplicateSale = await db('sales').select('phone_id').count('* as n')
    .groupBy('phone_id').havingRaw('COUNT(*) > 1').first();
  if (duplicateSale) {
    throw new Error(`Cannot enforce one-sale-per-phone: phone_id ${duplicateSale.phone_id} has ${duplicateSale.n} sales. Audit those rows before restarting.`);
  }
  await db.raw('CREATE UNIQUE INDEX IF NOT EXISTS sales_phone_id_unique ON sales (phone_id)');

  // Super admin seed
  const u = process.env.SUPERADMIN_USERNAME || 'superadmin';
  if (!(await db('users').where({ username: u }).first())) {
    await db('users').insert({ username: u, name: 'Super Admin', role: 'superadmin',
      password_hash: bcrypt.hashSync(process.env.SUPERADMIN_PASSWORD || 'Admin@123', 10) });
    console.log(`Super admin created -> ${u}`);
  }
  // Kuch sample TAC (baaki app use karte-karte khud seekhega / CSV import)
  const seed = [
    ['35332811', 'Apple', 'iPhone 13', '4GB', '128GB'],
    ['35391110', 'Samsung', 'Galaxy S21', '8GB', '128GB'],
    ['86769904', 'Xiaomi', 'Redmi Note 10', '4GB', '64GB'],
  ];
  for (const [tac, brand, model, ram, storage] of seed) {
    if (!(await db('tac_models').where({ tac }).first()))
      await db('tac_models').insert({ tac, brand, model, ram, storage });
  }
}
module.exports = migrate;
if (require.main === module) migrate().then(() => { console.log('Migration done'); process.exit(0); });
