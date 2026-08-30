import { FastifyInstance } from 'fastify';
import fs from 'fs';
import fsPromises from 'fs/promises';
import path from 'path';
import { config } from '../config.js';
import { authenticateUser, requirePermission } from '../middleware/auth.js';
import {
  MediaPurpose,
  persistMediaUpload,
} from '../services/mediaStorageService.js';

export function requestBaseUrl(request: {
  protocol: string;
  host: string;
}): string {
  // `hostname` intentionally drops the port. That produced unusable
  // `http://127.0.0.1/uploads/...` URLs during LAN/local API use even though
  // the service listens on :3001. Fastify's `host` keeps the port and, with
  // trustProxy enabled, also respects Cloudflare's forwarded public host.
  return `${request.protocol}://${request.host}`;
}

const publicMediaPathPattern =
  /^(avatar|announcement|post|challenge|player_card)\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|png|webp|gif)$/i;
const mediaTypeByExtension: Readonly<Record<string, string>> = {
  jpg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  gif: 'image/gif',
};

export async function publicMediaRoutes(fastify: FastifyInstance) {
  fastify.get('/uploads/*', async (request, reply) => {
    const wildcard = (request.params as { '*': string })['*'];
    if (!publicMediaPathPattern.test(wildcard)) {
      return reply.status(404).send({ error: 'NotFound', message: 'Image not found.' });
    }

    const normalized = path.posix.normalize(wildcard);
    const absolutePath = path.resolve(config.uploads.directory, normalized);
    const uploadsRoot = `${path.resolve(config.uploads.directory)}${path.sep}`;
    if (!absolutePath.startsWith(uploadsRoot)) {
      return reply.status(404).send({ error: 'NotFound', message: 'Image not found.' });
    }

    try {
      const stat = await fsPromises.stat(absolutePath);
      if (!stat.isFile()) throw new Error('not-file');
    } catch (_) {
      return reply.status(404).send({ error: 'NotFound', message: 'Image not found.' });
    }

    const extension = normalized.split('.').pop()!.toLowerCase();
    return reply
      .type(mediaTypeByExtension[extension])
      .header('Cache-Control', 'public, max-age=31536000, immutable')
      .header('Cross-Origin-Resource-Policy', 'cross-origin')
      .send(fs.createReadStream(absolutePath));
  });
}

async function receiveImage(request: any, purpose: MediaPurpose) {
  const part = await request.file();
  if (!part) {
    throw Object.assign(new Error('Attach one image using the "file" field.'), {
      statusCode: 400,
    });
  }
  if (part.fieldname !== 'file') {
    throw Object.assign(new Error('The multipart image field must be named "file".'), {
      statusCode: 400,
    });
  }

  const bytes = await part.toBuffer();
  return persistMediaUpload({
    userId: request.user.id,
    purpose,
    bytes,
    declaredContentType: part.mimetype,
    requestBaseUrl: requestBaseUrl(request),
  });
}

export async function uploadRoutes(fastify: FastifyInstance) {
  fastify.post(
    '/uploads/avatar',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 10, timeWindow: '1 hour' } },
    },
    async (request, reply) => {
      try {
        const upload = await receiveImage(request, 'avatar');
        return {
          success: true,
          uploadId: upload.id,
          url: upload.public_url,
          contentType: upload.content_type,
          sizeBytes: upload.size_bytes,
        };
      } catch (error: any) {
        if (error?.statusCode) throw error;
        return reply.status(400).send({
          error: 'InvalidImage',
          message: error?.message || 'Unable to store the image.',
        });
      }
    },
  );

  const permissionByPurpose: Readonly<Record<string, string>> = {
    announcement: 'notifications.send',
    post: 'challenges.manage',
    challenge: 'challenges.manage',
    player_card: 'player_cards.manage',
  };

  fastify.post('/admin/uploads/:purpose', async (request, reply) => {
    const { purpose } = request.params as { purpose: string };
    const permission = permissionByPurpose[purpose];
    if (!permission) {
      return reply.status(400).send({
        error: 'ValidationError',
        message: 'Unsupported admin upload purpose.',
      });
    }

    const guard = requirePermission(permission);
    await guard(request, reply);
    if (reply.sent) return;

    try {
      const upload = await receiveImage(request, purpose as MediaPurpose);
      return {
        success: true,
        uploadId: upload.id,
        url: upload.public_url,
        contentType: upload.content_type,
        sizeBytes: upload.size_bytes,
      };
    } catch (error: any) {
      if (error?.statusCode) throw error;
      return reply.status(400).send({
        error: 'InvalidImage',
        message: error?.message || 'Unable to store the image.',
      });
    }
  });
}
