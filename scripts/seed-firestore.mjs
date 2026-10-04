import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import admin from 'firebase-admin';

const rootDir = process.cwd();
const credentialsPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ||
  path.join(rootDir, 'secrets', 'firebase-service-account.json');
const seedPath =
  process.env.FIRESTORE_SEED_FILE ||
  path.join(rootDir, 'seed', 'demo-firestore-data.json');

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

if (!fs.existsSync(credentialsPath)) {
  console.error(
    `Missing service account JSON at "${credentialsPath}". ` +
      'Download it from Firebase Console > Project settings > Service accounts.',
  );
  process.exit(1);
}

if (!fs.existsSync(seedPath)) {
  console.error(`Missing seed data file at "${seedPath}".`);
  process.exit(1);
}

const serviceAccount = readJson(credentialsPath);
const seedData = readJson(seedPath);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function upsertCollection(collectionName, docs) {
  if (!Array.isArray(docs) || docs.length === 0) {
    return 0;
  }

  const batch = db.batch();

  for (const entry of docs) {
    const { id, ...data } = entry;
    if (!id) {
      throw new Error(`Document in "${collectionName}" is missing an "id" field.`);
    }

    const docRef = db.collection(collectionName).doc(String(id));
    batch.set(docRef, data, { merge: true });
  }

  await batch.commit();
  return docs.length;
}

async function main() {
  const restaurantsCount = await upsertCollection(
    'restaurants',
    seedData.restaurants,
  );

  const usersCount = await upsertCollection('users', seedData.users);
  const ordersCount = await upsertCollection('orders', seedData.orders);

  console.log(
    [
      `Seeded restaurants: ${restaurantsCount}`,
      `Seeded users: ${usersCount}`,
      `Seeded orders: ${ordersCount}`,
    ].join('\n'),
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Firestore seed failed.');
    console.error(error);
    process.exit(1);
  });
