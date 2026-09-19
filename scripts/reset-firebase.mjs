// Remise à zéro des données de test Snap'It (Firebase).
// ⚠️ IRRÉVERSIBLE : supprime TOUS les groupes, photos et profils.
//
// Utilisation :
//   1) Télécharge ta clé de service : Firebase Console → ⚙️ Paramètres du projet
//      → « Comptes de service » → « Générer une nouvelle clé privée » (JSON).
//   2) Dans un dossier à part :
//        mkdir ~/reset-snapit && cd ~/reset-snapit
//        npm init -y && npm i firebase-admin
//        # copie ce fichier + la clé (renommée serviceAccount.json) dans ce dossier
//   3) Lance :
//        node reset-firebase.mjs            # vide groups + users (Firestore)
//        node reset-firebase.mjs --auth     # + supprime aussi les comptes de connexion
//
// (Le chemin de la clé peut aussi être donné via SA_PATH=/chemin/cle.json)

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';

const KEY_PATH = process.env.SA_PATH || './serviceAccount.json';
const sa = JSON.parse(readFileSync(KEY_PATH, 'utf8'));

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const DELETE_AUTH = process.argv.includes('--auth');

async function wipeCollection(name) {
  console.log(`Suppression de la collection "${name}" (et ses sous-collections)…`);
  await db.recursiveDelete(db.collection(name));
  console.log(`  ✓ "${name}" vidée`);
}

async function wipeAuth() {
  console.log('Suppression des comptes Auth (connexion)…');
  let next;
  do {
    const res = await admin.auth().listUsers(1000, next);
    const uids = res.users.map((u) => u.uid);
    if (uids.length) await admin.auth().deleteUsers(uids);
    next = res.pageToken;
  } while (next);
  console.log('  ✓ comptes Auth supprimés');
}

(async () => {
  await wipeCollection('groups'); // inclut members/ et photos/
  await wipeCollection('users');
  if (DELETE_AUTH) await wipeAuth();
  console.log('✅ Remise à zéro terminée.');
  process.exit(0);
})().catch((e) => {
  console.error('Erreur :', e);
  process.exit(1);
});
