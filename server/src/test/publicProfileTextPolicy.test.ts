import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { describe, it } from 'node:test';
import {
  isPublicProfileTextAllowed,
  publicProfileTextViolation,
  safeInitialDisplayName,
  unsafePublicProfileTextError,
} from '../services/publicProfileTextPolicy.js';

describe('public profile text safety', () => {
  it('allows ordinary Latin and Arabic football profile names', () => {
    for (const value of [
      'Omar Jabur',
      'عمر جابور',
      'real_madrid_7',
      'Classic Football Fan',
      // A substring must not turn an otherwise normal name into a match.
      'Scunthorpe Fan',
    ]) {
      assert.equal(publicProfileTextViolation(value), null, value);
      assert.equal(isPublicProfileTextAllowed(value), true, value);
    }
  });

  it('rejects obvious abusive, sexual, and hate terms including simple evasion', () => {
    for (const value of [
      'f.u.c.k',
      'n1gg3r',
      'porn_player',
      'Nazi fan',
      'كس امك',
      'شرموطة',
    ]) {
      assert.equal(publicProfileTextViolation(value), 'offensive_language', value);
    }
  });

  it('rejects URLs, direct contact details, and contact solicitation', () => {
    for (const value of [
      'https://example.com/me',
      'my-profile.example.com',
      'joinme.dev',
      'evil.se/profile',
      'evil.se, message me',
      'bit.ly/foo',
      'support.example.photography/contact',
      'مثال.موقع',
      'omar@example.com',
      '+46 70 123 45 67',
      '@private_handle',
    ]) {
      assert.equal(publicProfileTextViolation(value), 'contact_details', value);
    }
    for (const value of [
      'DM me',
      'dm_me',
      'WhatsApp Omar',
      'راسلني',
      'تواصل معي',
    ]) {
      assert.equal(publicProfileTextViolation(value), 'contact_solicitation', value);
    }
  });

  it('rejects control/format characters and returns a stable value-free error', () => {
    assert.equal(
      publicProfileTextViolation('Omar\nAdmin'),
      'control_characters',
    );
    assert.equal(
      publicProfileTextViolation('Omar\u202EAdmin'),
      'control_characters',
    );
    assert.deepEqual(unsafePublicProfileTextError, {
      error: 'UnsafePublicProfileText',
      message:
        'Choose a different username or display name. Links, contact details, and offensive language are not allowed.',
    });
    assert.doesNotMatch(
      JSON.stringify(unsafePublicProfileTextError),
      /Omar|Admin|submittedValue/,
    );
  });

  it('replaces unsafe Firebase display text with a neutral identity fallback', () => {
    assert.equal(safeInitialDisplayName('Omar Jabur', 'Fan 123ABC'), 'Omar Jabur');
    assert.equal(safeInitialDisplayName('https://spam.example', 'Fan 123ABC'), 'Fan 123ABC');
    assert.equal(safeInitialDisplayName('x'.repeat(101), 'Fan 123ABC'), 'Fan 123ABC');
  });

  it('enforces the same policy in profile updates and account provisioning', async () => {
    const [profileRoutes, auth] = await Promise.all([
      readFile(path.resolve(process.cwd(), 'src/routes/profileRoutes.ts'), 'utf8'),
      readFile(path.resolve(process.cwd(), 'src/middleware/auth.ts'), 'utf8'),
    ]);
    assert.match(profileRoutes, /isPublicProfileTextAllowed\(displayName\)/);
    assert.match(profileRoutes, /isPublicProfileTextAllowed\(username\)/);
    assert.match(profileRoutes, /status\(400\)\.send\(unsafePublicProfileTextError\)/);
    assert.doesNotMatch(profileRoutes, /UnsafePublicProfileText[^\n]*displayName/);
    assert.match(auth, /safeInitialDisplayName/);
    assert.match(auth, /isPublicProfileTextAllowed\(usernameCandidate\)/);
  });
});
