import { FastifyInstance } from 'fastify';
import { config } from '../config.js';

/** Only a business phone number can become a public link, never an arbitrary URL. */
export function whatsappSupportUrl(value: string): string | null {
  const number = value.trim();
  return /^[1-9][0-9]{5,14}$/.test(number) ? `https://wa.me/${number}` : null;
}

export async function supportRoutes(
  fastify: FastifyInstance,
  dependencies: { number?: () => string } = {},
) {
  fastify.get('/support/contact', async (_request, reply) => {
    reply.header('Cache-Control', 'no-store');
    return {
      data: {
        whatsappUrl: whatsappSupportUrl(
          (dependencies.number ?? (() => config.support.whatsappNumber))(),
        ),
      },
    };
  });
}
