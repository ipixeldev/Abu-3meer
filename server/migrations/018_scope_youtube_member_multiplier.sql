-- YouTube members receive 2x points only for predictions and video answers.
-- Signup, daily attendance and Player Card discovery always use base points.
UPDATE point_rules
SET member_multiplier = 1.00,
    updated_at = CURRENT_TIMESTAMP
WHERE key IN ('signUpBonus', 'dailyStreak', 'playerCard');

-- Keep legacy challenge metadata consistent with the authoritative award
-- calculation so clients never advertise a doubled Player Card reward.
UPDATE challenges
SET member_points = reward_points
WHERE kind = 'playerCard'
  AND member_points <> reward_points;
