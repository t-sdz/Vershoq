// Remise à zéro des données de test Snap'It (Firebase).
// ⚠️ IRRÉVERSIBLE : supprime TOUS les groupes, photos et profils.
//
// Utilisation :
//   1) Télécharge ta clé de service : Firebase Console → ⚙️ Paramètres du projet
//      → « Comptes de service » → « Générer une nouvelle clé privée » (JSON).
//   2) Dans un dossier à part :
//        mkdir ~/reset-snapit && cd ~/reset-snapit
//        npm init -y && npm i firebase-admin
//        # copie ce fichier + la clé dans ce dossier
//   3) Lance (SA_PATH = chemin vers ta clé) :
//        SA_PATH=/chemin/cle.json node reset-firebase.mjs            # vide Firestore
//        SA_PATH=/chemin/cle.json node reset-firebase.mjs --auth     # + comptes de connexion
//     (par défaut il cherche ./serviceAccount.json)

import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

const KEY_PATH = process.env.SA_PATH || './serviceAccount.json';
const sa = JSON.parse(readFileSync(KEY_PATH, 'utf8'));

initializeApp({ credential: cert(sa) });
const db = getFirestore();

const DELETE_AUTH = process.argv.includes('--auth');

async function wipeCollection(name) {
  console.log(`Suppression de la collection "${name}" (et ses sous-collections)…`);
  await db.recursiveDelete(db.collection(name));
  console.log(`  ✓ "${name}" vidée`);
}

async function wipeAuth() {
  const auth = getAuth();
  console.log('Suppression des comptes Auth (connexion)…');
  let next;
  do {
    const res = await auth.listUsers(1000, next);
    const uids = res.users.map((u) => u.uid);
    if (uids.length) await auth.deleteUsers(uids);
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
