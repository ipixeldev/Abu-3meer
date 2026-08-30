import crypto from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import { config } from '../config.js';
import { query } from '../db/pool.js';

export type MediaPurpose =
  | 'avatar'
  | 'announcement'
  | 'post'
  | 'challenge'
  | 'player_card';

const MIME_EXTENSIONS: Readonly<Record<string, string>> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
};

export function detectImageContentType(bytes: Uint8Array): string | null {
  if (
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) {
    return 'image/jpeg';
  }
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) {
    return 'image/png';
  }
  if (
    bytes.length >= 12 &&
    Buffer.from(bytes.subarray(0, 4)).toString('ascii') === 'RIFF' &&
    Buffer.from(bytes.subarray(8, 12)).toString('ascii') === 'WEBP'
  ) {
    return 'image/webp';
  }
  if (bytes.length >= 6) {
    const signature = Buffer.from(bytes.subarray(0, 6)).toString('ascii');
    if (signature === 'GIF87a' || signature === 'GIF89a') {
      return 'image/gif';
    }
  }
  return null;
}

export function normalizedPublicBaseUrl(configuredBase: string, requestBase: string): string {
  const selected = configuredBase.trim() || requestBase.trim();
  return selected.replace(/\/+$/, '');
}

export interface PersistMediaParams {
  userId: string;
  purpose: MediaPurpose;
  bytes: Buffer;
  declaredContentType?: string;
  requestBaseUrl: string;
}

export async function persistMediaUpload(params: PersistMediaParams) {
  if (params.bytes.length === 0) {
    throw new Error('The uploaded image is empty.');
  }
  if (params.bytes.length > config.uploads.maxImageBytes) {
    throw new Error('The uploaded image exceeds the 8 MB limit.');
  }

  const detectedContentType = detectImageContentType(params.bytes);
  if (!detectedContentType) {
    throw new Error('Upload a valid JPG, PNG, WebP, or GIF image.');
  }
  if (
    params.declaredContentType &&
    params.declaredContentType !== 'application/octet-stream' &&
    params.declaredContentType.toLowerCase() !== detectedContentType
  ) {
    throw new Error('The uploaded file content does not match its image type.');
  }

  const extension = MIME_EXTENSIONS[detectedContentType];
  const relativeDirectory = path.posix.join(params.purpose, params.userId);
  const fileName = `${crypto.randomUUID()}.${extension}`;
  const relativePath = path.posix.join(relativeDirectory, fileName);
  const absoluteDirectory = path.join(
    config.uploads.directory,
    params.purpose,
    params.userId,
  );
  const absolutePath = path.join(absoluteDirectory, fileName);
  const baseUrl = normalizedPublicBaseUrl(
    config.uploads.publicBaseUrl,
    params.requestBaseUrl,
  );
  const publicUrl = `${baseUrl}/uploads/${relativePath}`;

  await fs.mkdir(absoluteDirectory, { recursive: true });
  await fs.writeFile(absolutePath, params.bytes, { flag: 'wx', mode: 0o640 });

  try {
    const result = await query(
      `INSERT INTO media_uploads
         (user_id, purpose, storage_path, public_url, content_type, size_bytes)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, purpose, public_url, content_type, size_bytes, created_at`,
      [
        params.userId,
        params.purpose,
        relativePath,
        publicUrl,
        detectedContentType,
        params.bytes.length,
      ],
    );
    return result.rows[0];
  } catch (error) {
    await fs.unlink(absolutePath).catch(() => undefined);
    throw error;
  }
}
