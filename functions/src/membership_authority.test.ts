import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

test("legacy Firebase functions cannot grant YouTube membership", () => {
  const source = fs.readFileSync(
    path.resolve(process.cwd(), "src/index.ts"),
    "utf8",
  );

  assert.match(
    source,
    /function hasVerifiedMembership[\s\S]{0,400}return false;/,
  );
  assert.match(
    source,
    /const membershipMultiplier = 1;/,
  );
  assert.match(
    source,
    /adminSetYouTubeMembership[\s\S]{0,500}Manual YouTube membership assignment is disabled/,
  );
  assert.doesNotMatch(
    source,
    /adminSetYouTubeMembership[\s\S]{0,1500}transaction\.update/,
  );
});
