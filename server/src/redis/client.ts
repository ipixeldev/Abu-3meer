import { Redis } from 'ioredis';
import { config } from '../config.js';

export const redis = new Redis({
  host: config.redis.host,
  port: config.redis.port,
  password: config.redis.password,
  lazyConnect: true,
  enableOfflineQueue: false,
  maxRetriesPerRequest: null,
  retryStrategy(times) {
    if (times > 5) return null;
    return Math.min(times * 100, 2000);
  },
});

redis.on('error', (err) => {
  if (config.env !== 'test') {
    console.error('[Redis] Connection Error:', err.message);
  }
});

redis.on('connect', () => {
  console.log('[Redis] Connected successfully.');
});

export async function getCachedJson<T>(key: string): Promise<T | null> {
  const data = await redis.get(key);
  if (!data) return null;
  try {
    return JSON.parse(data) as T;
  } catch {
    return null;
  }
}

export async function setCachedJson(key: string, value: any, ttlSeconds: number = 60): Promise<void> {
  await redis.set(key, JSON.stringify(value), 'EX', ttlSeconds);
}

export async function invalidateCachePattern(pattern: string): Promise<void> {
  const stream = redis.scanStream({ match: pattern, count: 100 });
  stream.on('data', async (keys: string[]) => {
    if (keys.length) {
      await redis.del(...keys);
    }
  });
}

export async function acquireLock(lockKey: string, ttlSeconds: number = 30): Promise<boolean> {
  const res = await redis.set(`lock:${lockKey}`, 'locked', 'EX', ttlSeconds, 'NX');
  return res === 'OK';
}

export async function releaseLock(lockKey: string): Promise<void> {
  await redis.del(`lock:${lockKey}`);
}
