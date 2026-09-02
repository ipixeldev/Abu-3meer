import { FastifyInstance } from 'fastify';
import { requirePermission } from '../middleware/auth.js';
import {
  adminDashboardStatsPath,
  getAdminDashboardStats,
} from '../services/adminStatsService.js';

/**
 * Aggregate-only Admin Studio routes live in their own plugin so their
 * registration can be verified without loading notification queues or Redis.
 */
export async function adminStatsRoutes(fastify: FastifyInstance) {
  fastify.get(
    adminDashboardStatsPath,
    { preHandler: [requirePermission('admin_dashboard.view')] },
    async () => getAdminDashboardStats(),
  );
}
