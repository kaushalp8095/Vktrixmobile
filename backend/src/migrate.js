const db = require('./db');
const bcrypt = require('bcryptjs');

async function migrate() {
  if (!(await db.schema.hasTable('shops'))) {
    await db.schema.createTable('shops', t => {
      t.increments('id');
      t.string('name').notNullable();
      t.string('owner_name'); t.string('phone'); t.string('address'); t.string('gst_no');
      // Small JPEG/PNG/WebP data URL used on customer-facing PDF receipts.
      t.text('logo_data');
      t.boolean('active').defaultTo(true);
      t.timestamp('created_at').defaultTo(db.fn.now());
    });
  }
  // Chhota key/value table: one-time backfills (jaise logo crop) ek hi baar
  // chalne chahiye, har boot par nahi.
  if (!(await db.schema.hasTable('meta'))) {
    await db.schema.createTable('meta', t => {
      t.string('key').notNullable().primary();
      t.text('value');
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
      t.string('source', 16);                // osmocom | tacdb | learned | csv | api | seed | legacy
      t.timestamp('updated_at').defaultTo(db.fn.now());
    });
  }
  if (!(await db.schema.hasTable('tac_sync_runs'))) {
    await db.schema.createTable('tac_sync_runs', t => {
      t.increments('id');
      t.string('source', 16).notNullable();  // osmocom | tacdb
      t.string('url', 500);
      t.string('status', 16).notNullable();  // running | success | failed
      t.timestamp('started_at').notNullable();
      t.timestamp('finished_at');
      t.integer('started_by').references('users.id').onDelete('SET NULL');
      t.integer('bytes'); t.integer('rows_seen'); t.integer('invalid');
      t.integer('inserted'); t.integer('updated'); t.integer('unchanged'); t.integer('protected');
      t.text('error');
      t.index(['status']);
    });
  }
  // Super Admin ka temporary, reason-logged, read-only support access.
  // Har row ek session hai: kaun (user_id), kis shop ka, kyun (reason), kitne
  // minute ke liye, aur us session me kitni baar data padha gaya / contact
  // reveal hua. Shop owner yahi log apni app me dekhta hai.
  if (!(await db.schema.hasTable('support_access'))) {
    await db.schema.createTable('support_access', t => {
      t.increments('id');
      t.integer('shop_id').notNullable().references('shops.id').onDelete('CASCADE');
      t.integer('user_id').references('users.id').onDelete('SET NULL');
      t.text('reason').notNullable();
      t.integer('minutes').notNullable();
      // Epoch milliseconds: SQLite aur PostgreSQL dono par ek jaisa compare hota hai
      // (timestamp strings ka timezone format dono DBs me alag hota hai).
      t.bigInteger('started_at_ms').notNullable();
      t.bigInteger('expires_at_ms').notNullable();
      t.bigInteger('ended_at_ms');
      t.integer('ended_by').references('users.id').onDelete('SET NULL');
      t.string('end_reason', 24);            // expired | admin_ended | shop_ended
      t.integer('read_count').notNullable().defaultTo(0);
      t.bigInteger('first_read_ms'); t.bigInteger('last_read_ms');
      t.integer('contact_reveals').notNullable().defaultTo(0);
      t.bigInteger('last_reveal_ms');
      t.timestamp('created_at').defaultTo(db.fn.now());
      t.index(['shop_id']); t.index(['expires_at_ms']);
    });
  }
  if (!(await db.schema.hasTable('phones'))) {
    await db.schema.createTable('phones', t => {
      t.increments('id');
      t.integer('shop_id').notNullable().references('shops.id').onDelete('CASCADE');
      t.string('imei', 15).notNullable();
      t.string('imei2', 15);
      t.string('serial_number', 64);                 // box/back pe likha hua serial (optional)
      t.string('brand'); t.string('model'); t.string('ram'); t.string('storage'); t.string('color');
      t.string('condition');                 // Excellent / Good / Fair / Faulty
      t.string('accessories');               // box, charger, bill
      t.decimal('buy_price', 12, 2).notNullable();
      t.date('buy_date').notNullable();
      t.string('seller_name'); t.string('seller_phone'); t.string('seller_id_type'); t.string('seller_id_no');
      t.string('seller_address');
      t.text('notes');
      t.text('customer_id_photo');                   // front / legacy single ID photo
      t.text('customer_id_photo_back');              // optional reverse side
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
      t.string('payment_mode').defaultTo('cash'); // cash | upi | card | bank | credit | emi
      t.string('warranty');
      t.text('notes');
      t.integer('created_by').references('users.id');
      t.timestamp('created_at').defaultTo(db.fn.now());
      t.index(['shop_id', 'sell_date']);
    });
  }

  // Every receipt can have zero or more collections. Keeping payments in their
  // own immutable rows gives an auditable partial-payment history instead of a
  // single balance that can silently be overwritten.
  let createdSalePayments = false;
  if (!(await db.schema.hasTable('sale_payments'))) {
    createdSalePayments = true;
    await db.schema.createTable('sale_payments', t => {
      t.increments('id');
      t.integer('shop_id').notNullable().references('shops.id').onDelete('CASCADE');
      t.integer('sale_id').notNullable().references('sales.id').onDelete('CASCADE');
      t.decimal('amount', 12, 2).notNullable();
      t.date('payment_date').notNullable();
      t.string('payment_mode', 24).notNullable(); // cash | upi | card | bank | other
      t.string('note', 500);
      t.integer('created_by').references('users.id').onDelete('SET NULL');
      t.timestamp('created_at').defaultTo(db.fn.now());
      t.index(['shop_id', 'sale_id']);
      t.index(['shop_id', 'payment_date']);
    });
  }

  // ---------- REPAIR JOBS (customer device service) ----------
  // Stock se alag rakha gaya hai jaan-boojh kar: customer ka phone shop ki
  // property nahi hai, isliye wo `phones` me nahi jaata. Warna stock value,
  // duplicate-IMEI check aur profit — teeno galat ho jate.
  //
  // `phone_id` tab bharta hai jab ye job shop ke **apne** stock phone ka ho
  // (faulty khareeda → repair → bechna) ya customer ka phone shop ne khareed
  // liya ho — us case me delivery par repair cost us phone ke cost me judta hai.
  if (!(await db.schema.hasTable('repairs'))) {
    await db.schema.createTable('repairs', t => {
      t.increments('id');
      t.integer('shop_id').notNullable().references('shops.id').onDelete('CASCADE');
      // RPR-<shop>-<id> — customer ko batane layak.
      t.string('job_no', 32);
      t.string('customer_name').notNullable();
      t.string('customer_phone');
      t.string('customer_address');
      // Device — IMEI optional (Tutela/feature phone me nahi hota), diya to Luhn valid.
      t.string('brand'); t.string('model');
      t.string('imei', 15); t.string('imei2', 15); t.string('serial_number', 64);
      t.string('color'); t.string('accessories');
      t.text('complaint').notNullable();
      t.text('diagnosis');
      t.text('notes');
      // Device lock (PIN/pattern) — sirf chhota note, PDF me kabhi nahi.
      t.string('device_lock_note', 255);
      // Paisa. estimate/charge 0 ho sakta hai (free checkup), parts internal.
      t.decimal('estimate', 12, 2).notNullable().defaultTo(0);
      t.decimal('service_charge', 12, 2).notNullable().defaultTo(0);
      t.decimal('parts_cost', 12, 2).notNullable().defaultTo(0);
      t.string('parts_note', 500);
      // received → repairing → ready → hold → delivered | cancelled
      t.string('status', 24).notNullable().defaultTo('received');
      t.date('received_at').notNullable();
      t.date('promised_date');
      t.date('delivered_at');
      t.integer('warranty_days');
      // Shop ke apne stock ka phone (case B), ya "convert to stock" par.
      t.integer('phone_id').references('phones.id').onDelete('SET NULL');
      t.integer('created_by').references('users.id').onDelete('SET NULL');
      t.timestamp('created_at').defaultTo(db.fn.now());
      t.timestamp('updated_at').defaultTo(db.fn.now());
      t.index(['shop_id', 'status']);
      t.index(['shop_id', 'promised_date']);
      t.index(['shop_id', 'imei']);
      t.index(['shop_id', 'customer_phone']);
    });
  }
  // Har receipt ki tarah repair me bhi zero ya zyada collections: advance alag
  // row, delivery par baaki alag. Balance kabhi silently overwrite nahi hota.
  if (!(await db.schema.hasTable('repair_payments'))) {
    await db.schema.createTable('repair_payments', t => {
      t.increments('id');
      t.integer('shop_id').notNullable().references('shops.id').onDelete('CASCADE');
      t.integer('repair_id').notNullable().references('repairs.id').onDelete('CASCADE');
      t.decimal('amount', 12, 2).notNullable();
      t.date('payment_date').notNullable();
      t.string('payment_mode', 24).notNullable().defaultTo('cash');
      t.string('note', 500);
      t.string('kind', 16).notNullable().defaultTo('payment'); // advance | payment | refund
      t.integer('created_by').references('users.id').onDelete('SET NULL');
      t.timestamp('created_at').defaultTo(db.fn.now());
      t.index(['shop_id', 'repair_id']);
      t.index(['shop_id', 'payment_date']);
    });
  }

  // Additive, idempotent migrations for existing deployments.
  if (!(await db.schema.hasColumn('users', 'token_version'))) {
    await db.schema.alterTable('users', t => t.integer('token_version').notNullable().defaultTo(0));
  }
  if (!(await db.schema.hasColumn('tac_models', 'source'))) {
    await db.schema.alterTable('tac_models', t => t.string('source', 16));
  }
  // Rows from before provenance tracking (learned purchases or old CSV imports)
  // are marked "legacy" so the community sync treats them as protected.
  await db('tac_models').whereNull('source').update({ source: 'legacy' });
  // A sync runs inside the API process; after a restart any "running" row is dead.
  await db('tac_sync_runs').where({ status: 'running' })
    .update({ status: 'failed', finished_at: new Date().toISOString(), error: 'Interrupted by server restart' });
  if (!(await db.schema.hasColumn('sales', 'buy_price_at_sale'))) {
    await db.schema.alterTable('sales', t => t.decimal('buy_price_at_sale', 12, 2));
  }
  if (!(await db.schema.hasColumn('sales', 'customer_id_type'))) {
    await db.schema.alterTable('sales', t => t.string('customer_id_type'));
  }
  if (!(await db.schema.hasColumn('sales', 'customer_id_photo'))) {
    await db.schema.alterTable('sales', t => t.text('customer_id_photo'));
  }
  if (!(await db.schema.hasColumn('sales', 'customer_id_photo_back'))) {
    await db.schema.alterTable('sales', t => t.text('customer_id_photo_back'));
  }
  // Repair cost jo shop ne apne stock phone par lagaya (parts + labour). Sale
  // par ye cost `buy_price` ke upar judta hai, warna profit zyada dikhta hai.
  if (!(await db.schema.hasColumn('phones', 'repair_cost'))) {
    await db.schema.alterTable('phones', t => t.decimal('repair_cost', 12, 2).notNullable().defaultTo(0));
  }
  if (!(await db.schema.hasColumn('shops', 'logo_data'))) {
    await db.schema.alterTable('shops', t => t.text('logo_data'));
  }
  // Shop list ke rows me chhota logo dikhane ke liye (poora base64 list me nahi
  // jaata). Naya logo aane par admin route ise bana deta hai; ye column purane
  // logos ke liye hai.
  if (!(await db.schema.hasColumn('shops', 'logo_thumb'))) {
    await db.schema.alterTable('shops', t => t.text('logo_thumb'));
  }
  // Purane logos ko bhi naye "auto-adjust" roop me laate hain: 512px **full-bleed**
  // square tile (margin trim + centre square crop) + 128px list thumbnail. Warna
  // already-uploaded logo box me patti ke saath / chhota floating dikhta rehta.
  //
  // Ek hi baar chalta hai (meta flag): crop badalne par dobara chalana padta hai,
  // par uske baad har boot par 300 logos decode karna fizool hai.
  {
    const thumb = require('./thumb');
    const FLAG = 'logo_full_bleed_v1';
    const done = await db('meta').where({ key: FLAG }).first().catch(() => null);
    if (!done) {
      const rows = await db('shops').whereNotNull('logo_data').andWhere('logo_data', '!=', '')
        .select('id', 'logo_data', 'logo_thumb').limit(300);
      let changed = 0;
      for (const row of rows) {
        let tiles = null;
        try { tiles = thumb.shopLogoTiles(row.logo_data, { force: true }); } catch { tiles = null; }
        const next = tiles
          ? { logo_data: tiles.logo, logo_thumb: tiles.thumb }
          // Auto-adjust na ho (PNG/WebP) to thumbnail khaali — warna har boot par
          // wahi fail hota rahega.
          : { logo_thumb: '' };
        if (next.logo_data === row.logo_data && next.logo_thumb === row.logo_thumb) continue;
        try {
          await db('shops').where({ id: row.id }).update(next);
          changed++;
        } catch { /* column/again next boot */ }
      }
      try {
        await db('meta').insert({ key: FLAG, value: String(Date.now()) });
      } catch { /* doosra instance pehle likh gaya */ }
      if (changed) console.log(`Shop logos full-bleed: ${changed}`);
    }
  }
  // On the one deployment where the ledger table is first introduced, preserve
  // old behaviour by marking non-credit historical sales as fully collected.
  // This runs only when the table was created, so a new unpaid sale can never be
  // mistaken for a legacy row on a later restart.
  if (createdSalePayments) {
    const oldPaidSales = await db('sales').whereNot({ payment_mode: 'credit' })
      .select('id', 'shop_id', 'sell_price', 'sell_date', 'payment_mode', 'created_by', 'created_at');
    if (oldPaidSales.length) {
      await db('sale_payments').insert(oldPaidSales.map(s => ({
        shop_id: s.shop_id, sale_id: s.id, amount: s.sell_price,
        payment_date: s.sell_date, payment_mode: ['cash', 'upi', 'card', 'bank'].includes(s.payment_mode) ? s.payment_mode : 'other',
        note: 'Opening balance migrated from existing sale', created_by: s.created_by, created_at: s.created_at,
      })));
    }
  }
  // Serial number (printed on the box / under the battery) and the customer ID photo.
  if (!(await db.schema.hasColumn('phones', 'serial_number'))) {
    await db.schema.alterTable('phones', t => t.string('serial_number', 64));
  }
  if (!(await db.schema.hasColumn('phones', 'customer_id_photo'))) {
    await db.schema.alterTable('phones', t => t.text('customer_id_photo'));
  }
  if (!(await db.schema.hasColumn('phones', 'customer_id_photo_back'))) {
    await db.schema.alterTable('phones', t => t.text('customer_id_photo_back'));
  }
  // The Buy form asks for RAM/storage/colour suggestions on every IMEI lookup,
  // matched case-insensitively on model and brand. Without these the sync can
  // leave ~250k TAC rows and each lookup would full-scan the catalog six times.
  await db.raw('CREATE INDEX IF NOT EXISTS tac_models_model_lower_idx ON tac_models (LOWER(model))');
  await db.raw('CREATE INDEX IF NOT EXISTS tac_models_brand_lower_idx ON tac_models (LOWER(brand))');
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
    const configured = (process.env.SUPERADMIN_PASSWORD || '').trim();
    // Pehle `Admin@123` default chhapta tha — var missing hone par internet par
    // khula panel known password ke saath. Prod me password ke bina seed hi nahi.
    if (!configured && process.env.NODE_ENV === 'production') {
      throw new Error('SUPERADMIN_PASSWORD is required to create the first super admin. '
        + 'Set it in the environment (Render → Environment) and redeploy.');
    }
    const password = configured || require('crypto').randomBytes(12).toString('base64url');
    await db('users').insert({ username: u, name: 'Super Admin', role: 'superadmin',
      password_hash: bcrypt.hashSync(password, 10) });
    console.log(configured
      ? `Super admin created -> ${u}`
      : `Super admin created -> ${u} / temporary password: ${password} (change it after login)`);
  }
  // Kuch sample TAC (baaki app use karte-karte khud seekhega / CSV import)
  const seed = [
    ['35332811', 'Apple', 'iPhone 13', '4GB', '128GB'],
    ['35391110', 'Samsung', 'Galaxy S21', '8GB', '128GB'],
    ['86769904', 'Xiaomi', 'Redmi Note 10', '4GB', '64GB'],
  ];
  for (const [tac, brand, model, ram, storage] of seed) {
    if (!(await db('tac_models').where({ tac }).first()))
      await db('tac_models').insert({ tac, brand, model, ram, storage, source: 'seed' });
  }
}
module.exports = migrate;
if (require.main === module) migrate().then(() => { console.log('Migration done'); process.exit(0); });
