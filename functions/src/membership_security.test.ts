import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import test from "node:test";

const firestoreRules = readFileSync(
  resolve(process.cwd(), "../firestore.rules"),
  "utf8",
);
const functionsSource = readFileSync(
  resolve(process.cwd(), "src/index.ts"),
  "utf8",
);

function topLevelMatchBlock(path: string): string {
  const lines = firestoreRules.split("\n");
  const start = lines.findIndex((line) => line.trim() === `match ${path} {`);
  assert.notEqual(start, -1, `Missing Firestore match block: ${path}`);

  let depth = 0;
  const block: string[] = [];
  for (let index = start; index < lines.length; index += 1) {
    const line = lines[index];
    block.push(line);
    depth += (line.match(/{/g) ?? []).length;
    depth -= (line.match(/}/g) ?? []).length;
    if (depth === 0) return block.join("\n");
  }
  assert.fail(`Unterminated Firestore match block: ${path}`);
}

test("Firestore users cannot create or mutate server-owned membership fields", () => {
  const protectedFields = [
    "isYouTubeMember",
    "membershipMultiplier",
    "youtubeMembershipVerifiedAt",
    "youtubeVerifiedAt",
    "youtubeChannelId",
    "youtubeMemberSince",
  ];
  for (const field of protectedFields) {
    assert.match(firestoreRules, new RegExp(`['\"]${field}['\"]`));
  }
  assert.match(
    firestoreRules,
    /allow create:[\s\S]*hasNoClientMembershipFields\(\)/,
  );
  assert.match(
    firestoreRules,
    /allow update:[\s\S]*keepsServerMembershipFields\(\)/,
  );
  assert.match(
    firestoreRules,
    /affectedKeys\(\)\.hasAny\(/,
  );
});

test("Firestore private account and activity collections are owner scoped", () => {
  const users = topLevelMatchBlock("/users/{uid}");
  assert.match(users, /allow get: if own\(uid\) \|\| admin\(\);/);
  assert.match(users, /allow list: if admin\(\);/);
  assert.doesNotMatch(users, /allow read: if signedIn\(\);/);

  for (const path of [
    "/predictions/{predictionId}",
    "/pointTransactions/{transactionId}",
  ]) {
    const block = topLevelMatchBlock(path);
    assert.match(
      block,
      /allow get, list: if admin\(\)[\s\S]*resource\.data\.userId == request\.auth\.uid/,
    );
    assert.doesNotMatch(block, /allow read: if signedIn\(\);/);
  }
});

test("Firestore prediction writes are restricted to trusted backend code", () => {
  const predictions = topLevelMatchBlock("/predictions/{predictionId}");
  assert.match(predictions, /allow create, update: if false;/);
  assert.match(predictions, /allow delete: if false;/);
});

test("Firestore reservation and UID-keyed leaderboard mirrors are server-only", () => {
  for (const path of [
    "/usernames/{username}",
    "/leaderboardEntries/{uid}",
  ]) {
    const block = topLevelMatchBlock(path);
    assert.match(block, /allow read, write: if false;/);
    assert.doesNotMatch(block, /allow read: if (true|signedIn\(\));/);
  }

  const seasons = topLevelMatchBlock("/leaderboardSeasons/{seasonId}");
  assert.match(seasons, /allow read: if signedIn\(\);/);
  assert.match(
    seasons,
    /match \/entries\/\{uid\} \{[\s\S]*allow read, write: if false;/,
  );
  assert.doesNotMatch(
    seasons,
    /match \/entries\/\{uid\} \{[\s\S]*allow read: if signedIn\(\);/,
  );
});

test("legacy Firebase-only account deletion fails closed", () => {
  const start = functionsSource.indexOf("export const deleteAccountData =");
  const end = functionsSource.indexOf(
    "export const verifyYouTubeMembership =",
    start,
  );
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  const callable = functionsSource.slice(start, end);

  assert.match(callable, /requireAuth\(request\.auth\)/);
  assert.match(callable, /new HttpsError\([\s\S]*"failed-precondition"/);
  assert.doesNotMatch(
    callable,
    /deleteUser|deleteFirebase|recursiveDelete|\.delete\(|runTransaction/,
  );
});
