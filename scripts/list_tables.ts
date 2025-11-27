import 'dotenv/config';
import { Client } from 'pg';

async function main() {
  try {
    console.error('Connecting...');
    const client = new Client({ connectionString: process.env.DATABASE_URL });
    await client.connect();
    console.error('Connected. Querying...');
    const res = await client.query(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'",
    );
    console.error('Tables:', res.rows);
    await client.end();
  } catch (e) {
    console.error('Error:', e);
  }
}
await main();
