export type PlayerCardQueryExecutor = (
  text: string,
  params?: unknown[],
) => Promise<{
  rowCount: number | null;
  rows: Array<Record<string, unknown>>;
}>;

/**
 * Returns the public catalogue plus cards already owned by this user. Disabled
 * unclaimed cards stay private, while disabling a definition never erases an
 * owner's collection.
 */
export async function listPlayerCardsForUser(
  execute: PlayerCardQueryExecutor,
  userId: string,
): Promise<Array<Record<string, unknown>>> {
  const result = await execute(
    `SELECT pc.id,
            CASE WHEN claim.id IS NOT NULL THEN pc.player_name ELSE '' END AS player_name,
            CASE WHEN claim.id IS NOT NULL THEN pc.player_name_ar ELSE '' END AS player_name_ar,
            CASE WHEN claim.id IS NOT NULL THEN pc.card_image_url ELSE '' END AS card_image_url,
            CASE WHEN claim.id IS NOT NULL THEN pc.team ELSE '' END AS team,
            CASE WHEN claim.id IS NOT NULL THEN pc.team_logo_url ELSE '' END AS team_logo_url,
            CASE WHEN claim.id IS NOT NULL THEN COALESCE(pc.position, '') ELSE '' END AS position,
            CASE WHEN claim.id IS NOT NULL THEN pc.rating ELSE 0 END AS rating,
            pc.rarity,
            CASE WHEN claim.id IS NOT NULL THEN pc.stats ELSE '{}'::jsonb END AS stats,
            CASE WHEN claim.id IS NOT NULL THEN pc.description ELSE '' END AS description,
            CASE WHEN claim.id IS NOT NULL THEN pc.description_ar ELSE '' END AS description_ar,
            pc.enabled,
            COALESCE(NULLIF(pc.source_challenge_id, ''), pc.challenge_id, '')
              AS source_challenge_id,
            claim.id IS NOT NULL AS unlocked,
            claim.claimed_at AS unlocked_at,
            pc.updated_at
     FROM player_cards pc
     LEFT JOIN player_card_claims claim
       ON claim.player_card_id = pc.id AND claim.user_id = $1
     WHERE claim.id IS NOT NULL
        OR (
          pc.enabled = TRUE
          AND EXISTS (
            SELECT 1
            FROM challenges challenge
            WHERE challenge.id = COALESCE(
              NULLIF(pc.source_challenge_id, ''),
              pc.challenge_id
            )
              AND challenge.status IN ('open', 'scheduled')
              AND challenge.starts_at <= CURRENT_TIMESTAMP
              AND challenge.ends_at >= CURRENT_TIMESTAMP
          )
        )
     ORDER BY pc.updated_at DESC
     LIMIT 200`,
    [userId],
  );
  return result.rows;
}
