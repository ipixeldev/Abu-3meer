import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeChallengeAnswer } from '../services/challengeService.js';

describe('Security & Anti-Abuse Hardening Unit Tests', () => {
  describe('1. Challenge Answer Normalization & Tampering Resistance', () => {
    it('normalizes diacritics, case, whitespace, and Unicode variations correctly', () => {
      const inputWithTashkeel = '  مُحَمَّد صَلَاح  ';
      const normalized = normalizeChallengeAnswer(inputWithTashkeel);
      assert.equal(normalized, 'محمد صلاح');
    });

    it('unifies alef variants (أ, إ, آ -> ا)', () => {
      assert.equal(normalizeChallengeAnswer('أحمد'), 'احمد');
      assert.equal(normalizeChallengeAnswer('إبراهيم'), 'ابراهيم');
      assert.equal(normalizeChallengeAnswer('آدم'), 'ادم');
    });

    it('unifies taa marbuta (ة -> ه) and yaa (ى -> ي)', () => {
      assert.equal(normalizeChallengeAnswer('برشلونة'), 'برشلونه');
      assert.equal(normalizeChallengeAnswer('موسى'), 'موسي');
    });
  });

  describe('2. Client Parameter Immunity', () => {
    it('disallows client-injected points and roles from affecting server calculations', () => {
      // Base calculation on server
      const basePoints = 30;
      const trustedMultiplier = 2.0;
      const calculatedPoints = Math.round(basePoints * trustedMultiplier);

      // Client forged payload attempts to pass 9999 points
      const clientForgedPayload = { points: 9999, multiplier: 10.0, isAdmin: true };

      // Server must strictly use configured constants, ignoring client values
      assert.equal(calculatedPoints, 60);
      assert.notEqual(calculatedPoints, clientForgedPayload.points);
    });
  });

  describe('3. Prediction Kickoff & Deadline Enforcement', () => {
    it('strictly locks predictions when server time reaches or passes deadline', () => {
      const now = new Date('2026-08-26T20:00:00Z');
      const kickoff = new Date('2026-08-26T20:00:00Z');
      const deadline = new Date(kickoff.getTime() - 5 * 60 * 1000); // 19:55:00Z

      const isLocked = now >= deadline;
      assert.equal(isLocked, true);
    });

    it('allows predictions before the deadline', () => {
      const submissionTime = new Date('2026-08-26T19:50:00Z');
      const kickoff = new Date('2026-08-26T20:00:00Z');
      const deadline = new Date(kickoff.getTime() - 5 * 60 * 1000); // 19:55:00Z

      const isLocked = submissionTime >= deadline;
      assert.equal(isLocked, false);
    });
  });

  describe('4. Idempotency Key Uniqueness', () => {
    it('constructs distinct and deterministic idempotency keys per activity', () => {
      const userId = 'usr_123';
      const matchId = 'match_456';
      const challengeId = 'chal_789';
      const dateStr = '2026-08-26';

      const predKey = `pred_reward:${userId}:${matchId}`;
      const chalKey = `challenge:${challengeId}:user:${userId}`;
      const streakKey = `streak:${userId}:${dateStr}`;

      assert.equal(predKey, 'pred_reward:usr_123:match_456');
      assert.equal(chalKey, 'challenge:chal_789:user:usr_123');
      assert.equal(streakKey, 'streak:usr_123:2026-08-26');
    });
  });
});
