import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  detectImageContentType,
  normalizedPublicBaseUrl,
} from '../services/mediaStorageService.js';
import { requestBaseUrl } from '../routes/uploadRoutes.js';

describe('self-hosted media storage validation', () => {
  it('recognizes supported image signatures instead of trusting file names', () => {
    assert.equal(
      detectImageContentType(Buffer.from([0xff, 0xd8, 0xff, 0xe0])),
      'image/jpeg',
    );
    assert.equal(
      detectImageContentType(
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      ),
      'image/png',
    );
    assert.equal(
      detectImageContentType(Buffer.from('GIF89a', 'ascii')),
      'image/gif',
    );
    assert.equal(
      detectImageContentType(Buffer.from('not really an image', 'utf8')),
      null,
    );
  });

  it('uses the configured tunnel base and removes trailing slashes', () => {
    assert.equal(
      normalizedPublicBaseUrl(
        'https://api.abu3meer.com/',
        'http://127.0.0.1:3001',
      ),
      'https://api.abu3meer.com',
    );
    assert.equal(
      normalizedPublicBaseUrl('', 'http://127.0.0.1:3001/'),
      'http://127.0.0.1:3001',
    );
  });

  it('keeps the request port in local upload URLs', () => {
    assert.equal(
      requestBaseUrl({ protocol: 'http', host: '127.0.0.1:3001' }),
      'http://127.0.0.1:3001',
    );
    assert.equal(
      requestBaseUrl({ protocol: 'https', host: 'api.abu3meer.com' }),
      'https://api.abu3meer.com',
    );
  });
});
