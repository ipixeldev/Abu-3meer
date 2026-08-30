import { z } from 'zod';

const integerFromClient = (minimum: number, maximum: number) => z.preprocess(
  (value) => {
    if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
      return Number(value.trim());
    }
    return value;
  },
  z.number().int().min(minimum).max(maximum),
);

const optionalText = (maximum: number) => z.preprocess(
  (value) => value === null || value === '' ? undefined : value,
  z.string().trim().min(1).max(maximum).optional(),
);

const optionalImageUrl = z.preprocess(
  (value) => value === '' ? undefined : value,
  z.string().max(500).optional().nullable(),
);

const kickoffFromClient = z.preprocess((value) => {
  let timestamp = value;
  if (typeof timestamp === 'string' && /^\d+$/.test(timestamp.trim())) {
    timestamp = Number(timestamp.trim());
  }
  if (typeof timestamp === 'number' && Number.isFinite(timestamp)) {
    // Native clients commonly serialize Unix timestamps either in seconds or
    // milliseconds. Normalize both to the same ISO value used internally.
    const milliseconds = timestamp < 10_000_000_000 ? timestamp * 1000 : timestamp;
    return new Date(milliseconds).toISOString();
  }
  return timestamp;
}, z.string().trim().refine(
  (value) => Number.isFinite(Date.parse(value)),
  'Invalid kickoff timestamp',
).transform((value) => new Date(value).toISOString()).optional());

export const predictionInputSchema = z.object({
  matchId: z.string().trim().min(1).max(100),
  homeScore: integerFromClient(0, 30),
  awayScore: integerFromClient(0, 30),
  firstScorer: z.preprocess(
    (value) => value === null || value === '' ? 'No scorer' : value,
    z.string().trim().max(150),
  ).default('No scorer'),
  homeTeam: optionalText(100),
  awayTeam: optionalText(100),
  competition: optionalText(100),
  kickoffAt: kickoffFromClient,
  homeLogoUrl: optionalImageUrl,
  awayLogoUrl: optionalImageUrl,
});

export function parsePredictionInputPayload(payload: unknown) {
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
    return predictionInputSchema.safeParse(payload);
  }
  const input = payload as Record<string, unknown>;
  // Camel case is canonical. The aliases keep requests from older native
  // builds compatible while all validation and limits remain server-owned.
  return predictionInputSchema.safeParse({
    ...input,
    matchId: input.matchId ?? input.match_id,
    homeScore: input.homeScore ?? input.home_score,
    awayScore: input.awayScore ?? input.away_score,
    firstScorer: input.firstScorer ?? input.first_scorer,
    homeTeam: input.homeTeam ?? input.home_team,
    awayTeam: input.awayTeam ?? input.away_team,
    competition: input.competition ?? input.competition_name,
    kickoffAt: input.kickoffAt ?? input.kickoff_at,
    homeLogoUrl: input.homeLogoUrl ?? input.home_logo_url,
    awayLogoUrl: input.awayLogoUrl ?? input.away_logo_url,
  });
}
