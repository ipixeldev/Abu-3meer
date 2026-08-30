import { FastifyInstance } from 'fastify';
import { authenticateUser } from '../middleware/auth.js';
import { submitPrediction } from '../services/predictionService.js';
import { parsePredictionInputPayload } from '../services/predictionInput.js';
import { getPointRules } from '../services/pointsService.js';
import { config } from '../config.js';
import { query } from '../db/pool.js';

export async function predictionRoutes(fastify: FastifyInstance) {
  const pointRulesHandler = async () => {
    const rules = await getPointRules();
    return {
      exactPrediction: rules.exactPrediction ?? config.pointDefaults.exactScore,
      firstScorer: rules.firstScorer ?? config.pointDefaults.firstScorer,
      winnerOutcome: rules.winnerOutcome ?? config.pointDefaults.winnerOutcome,
      videoQuestion: rules.videoQuestion ?? config.pointDefaults.videoPhrase,
      playerCard: rules.playerCard ?? config.pointDefaults.playerCard,
      dailyStreak: rules.dailyStreak ?? config.pointDefaults.dailyStreak,
      memberMultiplier: config.pointDefaults.memberMultiplier,
    };
  };

  // Public scoring rules let every client show the same rewards that the
  // server will enforce. The alias preserves compatibility with older builds.
  fastify.get('/point-rules', pointRulesHandler);
  fastify.get('/predictions/point-rules', pointRulesHandler);

  // POST /api/v1/predictions - Submit or update match prediction
  fastify.post('/predictions', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;

    const parsed = parsePredictionInputPayload(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: 'ValidationError',
        message: 'Invalid prediction parameters',
        issues: parsed.error.issues,
      });
    }

    try {
      const pred = await submitPrediction({
        userId: user.id,
        matchId: parsed.data.matchId,
        homeScore: parsed.data.homeScore,
        awayScore: parsed.data.awayScore,
        firstScorer: parsed.data.firstScorer,
        homeTeam: parsed.data.homeTeam,
        awayTeam: parsed.data.awayTeam,
        competition: parsed.data.competition,
        kickoffAt: parsed.data.kickoffAt,
        homeLogoUrl: parsed.data.homeLogoUrl,
        awayLogoUrl: parsed.data.awayLogoUrl,
      });
      return { success: true, prediction: pred };
    } catch (err: any) {
      const message = err?.message || 'Unable to submit prediction';
      if (message.includes('window')) {
        return reply.status(409).send({
          error: 'PredictionLockError',
          message,
        });
      }
      if (
        message.includes('required') ||
        message.includes('invalid') ||
        message.includes('prepared')
      ) {
        return reply.status(422).send({
          error: 'PredictionDataError',
          message,
        });
      }
      throw err;
    }
  });

  // GET /api/v1/predictions/my - Fetch authenticated user's own predictions
  fastify.get('/predictions/my', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const res = await query(
      `SELECT p.id, p.match_id, p.home_score, p.away_score, p.first_scorer,
              p.points_awarded, p.rewarded, p.seen_result,
              p.is_exact_match, p.is_first_scorer_match, p.is_winner_match,
              p.submitted_at, p.updated_at,
              m.home_team, m.away_team, m.home_logo_url, m.away_logo_url, m.kickoff_at,
              m.status as match_status, m.home_score as actual_home_score, m.away_score as actual_away_score,
              m.first_scorer as actual_first_scorer
       FROM predictions p
       JOIN matches m ON m.id = p.match_id
       WHERE p.user_id = $1
       ORDER BY p.submitted_at DESC`,
      [user.id]
    );
    return res.rows;
  });

  // POST /api/v1/predictions/:id/seen - Mark prediction result as seen by owner
  fastify.post('/predictions/:id/seen', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const { id } = request.params as { id: string };

    const updateRes = await query(
      'UPDATE predictions SET seen_result = true WHERE id = $1 AND user_id = $2 RETURNING id',
      [id, user.id]
    );

    if (updateRes.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: 'Prediction not found or not owned by you' });
    }

    return { success: true };
  });
}
