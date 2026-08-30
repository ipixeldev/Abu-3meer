import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import test from "node:test";

const firestoreRules = readFileSync(
  resolve(process.cwd(), "../firestore.rules"),
  "utf8",
);

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
