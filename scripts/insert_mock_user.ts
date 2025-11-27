import 'dotenv/config';

import { serverDB } from '../packages/database/src/core/db-adaptor';
import { users } from '../packages/database/src/schemas/user';

async function main() {
  console.log('Starting script...');
  console.log('DATABASE_DRIVER:', process.env.DATABASE_DRIVER);
  console.log('DATABASE_URL:', process.env.DATABASE_URL);
  console.log('Inserting mock user...');
  try {
    await serverDB
      .insert(users)
      .values({
        email: 'mock@example.com',
        id: 'user_123',
        username: 'mockuser',
      })
      .onConflictDoNothing();
    console.log('Mock user inserted successfully.');
  } catch (error) {
    console.error('Error inserting mock user:', error);
    throw error;
  }
}

await main();
