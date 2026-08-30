-- Player Cards are video challenges and receive the verified-member 2x bonus.
-- Signup and daily attendance remain intentionally fixed at base points.
UPDATE point_rules
SET member_multiplier = CASE
      WHEN key = 'playerCard' THEN 2.00
      ELSE 1.00
    END,
    updated_at = CURRENT_TIMESTAMP
WHERE key IN ('playerCard', 'signUpBonus', 'dailyStreak');

-- Keep the public challenge metadata aligned with the authoritative ledger.
UPDATE challenges
SET member_points = reward_points * 2
WHERE kind = 'playerCard'
  AND member_points <> reward_points * 2;
