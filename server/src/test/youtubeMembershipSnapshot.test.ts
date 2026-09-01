import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { describe, it } from 'node:test';
import {
  ParsedYouTubeMembershipSnapshot,
  ParsedYouTubeMembershipSnapshotRow,
  YouTubeMembershipSnapshotError,
  YouTubeMembershipSnapshotMetadata,
  YouTubeMembershipSnapshotStore,
  extractYouTubeChannelIdFromProfileLink,
  getActiveYouTubeMembershipSnapshot,
  getYouTubeMembershipSnapshotStatus,
  importYouTubeMembershipSnapshot,
  membershipLookupFromSnapshot,
  parseYouTubeMembershipSnapshot,
  youtubeMembershipSnapshotHeaders,
  youtubeMembershipSnapshotMaxAgeHours,
} from '../services/youtubeMembershipSnapshotService.js';

const now = new Date('2026-09-01T12:00:00Z');
const channelA = `UC${'a'.repeat(22)}`;
const channelB = `UC${'b'.repeat(22)}`;

function csv(rows: string[]): Buffer {
  return Buffer.from(
    `${youtubeMembershipSnapshotHeaders.join(',')}\n${rows.join('\n')}\n`,
    'utf8',
  );
}

class FakeSnapshotStore implements YouTubeMembershipSnapshotStore {
  metadata: YouTubeMembershipSnapshotMetadata | null = null;
  members: ParsedYouTubeMembershipSnapshotRow[] = [];
  replaced: Parameters<YouTubeMembershipSnapshotStore['replaceSnapshot']>[0][] = [];

  async replaceSnapshot(
    input: Parameters<YouTubeMembershipSnapshotStore['replaceSnapshot']>[0],
  ): Promise<YouTubeMembershipSnapshotMetadata> {
    this.replaced.push(input);
    this.members = input.parsed.rows;
    this.metadata = {
      importId: '5b3608bb-5bd6-4708-b1ab-ab30d52f3eed',
      sourceFilename: input.parsed.sourceFilename,
      sourceFormat: input.parsed.format,
      sourceSha256: input.parsed.sourceSha256,
      memberCount: input.parsed.rows.length,
      matchedUserCount: 1,
      activatedAt: input.activatedAt,
    };
    return this.metadata;
  }

  async getActiveMetadata() {
    return this.metadata;
  }

  async getMembers(_importId: string, channelIds: string[]) {
    const requested = new Set(channelIds);
    return this.members.filter((row) => requested.has(row.youtubeChannelId));
  }
}

describe('YouTube membership snapshot CSV/TSV parsing', () => {
  it('parses exact YouTube headers, quoted commas, and UTF-8 Arabic levels', () => {
    const parsed = parseYouTubeMembershipSnapshot({
      fileName: 'members.csv',
      bytes: csv([
        `"عضو, تجريبي",https://www.youtube.com/channel/${channelA},"المستوى الذهبي",3.5,12,"1 Sep 2026",1788264000`,
      ]),
    });

    assert.equal(parsed.format, 'csv');
    assert.equal(parsed.rows.length, 1);
    assert.equal(parsed.rows[0].youtubeChannelId, channelA);
    assert.equal(parsed.rows[0].membershipLevel, 'المستوى الذهبي');
    assert.equal(parsed.rows[0].totalTimeAsMemberMonths, 12);
    assert.equal(
      parsed.rows[0].sourceLastUpdateAt?.toISOString(),
      '2026-09-01T12:00:00.000Z',
    );
    assert.match(parsed.sourceSha256, /^[a-f0-9]{64}$/);
  });

  it('parses a UTF-8 BOM TSV export', () => {
    const row = [
      'Member name',
      `https://youtube.com/channel/${channelB}`,
      'عضو',
      '1',
      '2',
      'today',
      '2026-09-01T12:00:00Z',
    ].join('\t');
    const bytes = Buffer.concat([
      Buffer.from([0xef, 0xbb, 0xbf]),
      Buffer.from(`${youtubeMembershipSnapshotHeaders.join('\t')}\n${row}\n`),
    ]);
    const parsed = parseYouTubeMembershipSnapshot({
      fileName: 'members.tsv',
      bytes,
    });
    assert.equal(parsed.format, 'tsv');
    assert.equal(parsed.rows[0].membershipLevel, 'عضو');
  });

  it('rejects spreadsheets with an export-as-CSV message', () => {
    assert.throws(
      () => parseYouTubeMembershipSnapshot({
        fileName: 'members.xlsx',
        bytes: Buffer.from([0x50, 0x4b, 0x03, 0x04]),
      }),
      (error: unknown) =>
        error instanceof YouTubeMembershipSnapshotError &&
        error.code === 'youtube_snapshot_spreadsheet_unsupported' &&
        /Export.*UTF-8 CSV/i.test(error.message),
    );
  });

  it('rejects changed headers, duplicate channels, and non-channel links', () => {
    const wrongHeader = Buffer.from(
      `Name,${youtubeMembershipSnapshotHeaders.slice(1).join(',')}\n`,
    );
    assert.throws(
      () => parseYouTubeMembershipSnapshot({
        fileName: 'members.csv',
        bytes: wrongHeader,
      }),
      (error: unknown) =>
        error instanceof YouTubeMembershipSnapshotError &&
        error.code === 'youtube_snapshot_headers_invalid',
    );
    assert.throws(
      () => parseYouTubeMembershipSnapshot({
        fileName: 'members.csv',
        bytes: csv([
          `One,https://youtube.com/channel/${channelA},Gold,1,1,today,1788264000`,
          `Two,https://youtube.com/channel/${channelA},Gold,1,1,today,1788264000`,
        ]),
      }),
      (error: unknown) =>
        error instanceof YouTubeMembershipSnapshotError &&
        error.code === 'youtube_snapshot_duplicate_channel',
    );
    assert.throws(
      () => extractYouTubeChannelIdFromProfileLink(
        'https://youtube.example/channel/UCnottrusted',
      ),
      YouTubeMembershipSnapshotError,
    );
  });
});

describe('YouTube membership snapshot lifecycle', () => {
  it('migrates minimized snapshot and immutable import-audit tables', async () => {
    const migration = await readFile(
      path.resolve(
        process.cwd(),
        'migrations/033_youtube_membership_snapshots.sql',
      ),
      'utf8',
    );
    assert.match(migration, /youtube_membership_snapshot_imports/);
    assert.match(migration, /youtube_membership_snapshot_members/);
    assert.match(migration, /source_sha256/);
    assert.match(migration, /verification_source/);
    assert.doesNotMatch(
      migration,
      /member_display_name|profile_url|uploaded_(?:file|bytes|content)/i,
    );

    const lifecycleMigration = await readFile(
      path.resolve(
        process.cwd(),
        'migrations/034_youtube_membership_lifecycle.sql',
      ),
      'utf8',
    );
    assert.match(lifecycleMigration, /status IN \('active', 'lapsed'\)/);
    assert.match(lifecycleMigration, /joined_at TIMESTAMPTZ/);
    assert.match(lifecycleMigration, /last_seen_at TIMESTAMPTZ/);
    assert.match(lifecycleMigration, /left_at TIMESTAMPTZ/);
    assert.doesNotMatch(lifecycleMigration, /display_name|profile_url/i);
  });

  it('upserts present IDs and lapses missing IDs at the import timestamp', async () => {
    const service = await readFile(
      path.resolve(
        process.cwd(),
        'src/services/youtubeMembershipSnapshotService.ts',
      ),
      'utf8',
    );
    assert.match(service, /ON CONFLICT \(youtube_channel_id\) DO UPDATE SET/);
    assert.match(service, /status = 'active'/);
    assert.match(service, /SET status = 'lapsed',[\s\S]*left_at = \$2/);
    assert.match(service, /AND import_id <> \$1/);
    assert.doesNotMatch(service, /DELETE FROM youtube_membership_snapshot_members/);
  });

  it('imports a privacy-minimized snapshot with a sanitized filename and TTL', async () => {
    const store = new FakeSnapshotStore();
    const result = await importYouTubeMembershipSnapshot(
      {
        bytes: csv([
          `Private display name,https://youtube.com/channel/${channelA},Gold,2,8,today,1788264000`,
        ]),
        fileName: '../../My Member Export (private).csv',
        importedByUserId: 'admin-1',
      },
      {
        store,
        now,
        environment: { YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS: '24' },
      },
    );

    assert.equal(store.replaced.length, 1);
    assert.equal(result.sourceFilename, 'My_Member_Export_private_.csv');
    assert.equal(result.memberCount, 1);
    assert.equal(result.matchedUserCount, 1);
    assert.equal(result.expiresAt, '2026-09-02T12:00:00.000Z');
    assert.doesNotMatch(JSON.stringify(store.replaced), /Private display name/);
  });

  it('requires an explicit confirmation before a replacement lapses many members', async () => {
    const store = new FakeSnapshotStore();
    store.metadata = {
      importId: '5b3608bb-5bd6-4708-b1ab-ab30d52f3eed',
      sourceFilename: 'members.csv',
      sourceFormat: 'csv',
      sourceSha256: 'a'.repeat(64),
      memberCount: 10,
      matchedUserCount: 4,
      activatedAt: now,
    };
    const replacement = {
      bytes: csv([
        `One,https://youtube.com/channel/${channelA},Gold,1,1,Joined,2026-09-01T12:00:00Z`,
      ]),
      fileName: 'members.csv',
      importedByUserId: 'moderator-1',
    };

    await assert.rejects(
      () => importYouTubeMembershipSnapshot(replacement, { store, now }),
      (error: unknown) =>
        error instanceof YouTubeMembershipSnapshotError &&
        error.code ===
          'youtube_snapshot_large_decrease_confirmation_required' &&
        error.httpStatus === 409,
    );
    assert.equal(store.replaced.length, 0);

    const result = await importYouTubeMembershipSnapshot(
      { ...replacement, allowLargeDecrease: true },
      { store, now },
    );
    assert.equal(result.memberCount, 1);
    assert.equal(store.replaced.length, 1);
  });

  it('keeps the latest snapshot authoritative while reporting it as expired', async () => {
    const store = new FakeSnapshotStore();
    store.metadata = {
      importId: '5b3608bb-5bd6-4708-b1ab-ab30d52f3eed',
      sourceFilename: 'members.csv',
      sourceFormat: 'csv',
      sourceSha256: 'a'.repeat(64),
      memberCount: 1,
      matchedUserCount: 0,
      activatedAt: new Date('2026-08-30T12:00:00Z'),
    };
    store.members = [{
      youtubeChannelId: channelA,
      membershipLevel: 'Gold',
      totalTimeOnLevelMonths: 1,
      totalTimeAsMemberMonths: 2,
      sourceLastUpdate: null,
      sourceLastUpdateAt: null,
    }];
    const environment = { YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS: '24' };
    const snapshot = await getActiveYouTubeMembershipSnapshot([channelA], {
      store,
      now,
      environment,
    });
    assert.ok(snapshot);
    assert.equal(snapshot.members.has(channelA), true);
    assert.equal(
      membershipLookupFromSnapshot([channelA], snapshot).isMember,
      true,
      'staleness is a warning; the latest complete export remains authoritative',
    );
    const status = await getYouTubeMembershipSnapshotStatus({
      store,
      now,
      environment,
    });
    assert.equal(status.status, 'expired');
  });

  it('maps channel presence to membership and absence to not-member', async () => {
    const store = new FakeSnapshotStore();
    store.metadata = {
      importId: '5b3608bb-5bd6-4708-b1ab-ab30d52f3eed',
      sourceFilename: 'members.csv',
      sourceFormat: 'csv',
      sourceSha256: 'b'.repeat(64),
      memberCount: 1,
      matchedUserCount: 0,
      activatedAt: now,
    };
    store.members = [{
      youtubeChannelId: channelA,
      membershipLevel: 'Gold',
      totalTimeOnLevelMonths: 1,
      totalTimeAsMemberMonths: 6,
      sourceLastUpdate: null,
      sourceLastUpdateAt: null,
    }];
    const snapshot = await getActiveYouTubeMembershipSnapshot(
      [channelA, channelB],
      { store, now },
    );
    assert.ok(snapshot);
    assert.equal(
      membershipLookupFromSnapshot([channelA], snapshot).isMember,
      true,
    );
    assert.equal(
      membershipLookupFromSnapshot([channelA], snapshot).memberSince,
      null,
      'cumulative lifetime months must not be treated as a current join date',
    );
    assert.equal(
      membershipLookupFromSnapshot([channelB], snapshot).isMember,
      false,
    );
  });

  it('uses the Joined/Re-joined event timestamp for the current member period', async () => {
    const joinedAt = new Date('2026-08-17T09:15:04.998Z');
    const snapshot = {
      importId: '5b3608bb-5bd6-4708-b1ab-ab30d52f3eed',
      activatedAt: now,
      expiresAt: new Date('2026-09-08T12:00:00Z'),
      members: new Map([[channelA, {
        youtubeChannelId: channelA,
        membershipLevel: 'Gold',
        totalTimeOnLevelMonths: 1,
        totalTimeAsMemberMonths: 14,
        sourceLastUpdate: 'Re-joined',
        sourceLastUpdateAt: joinedAt,
      }]]),
    };

    const lookup = membershipLookupFromSnapshot([channelA], snapshot);
    assert.equal(lookup.isMember, true);
    assert.equal(lookup.memberSince?.toISOString(), joinedAt.toISOString());
  });

  it('validates the configurable snapshot age bound', () => {
    assert.equal(
      youtubeMembershipSnapshotMaxAgeHours({
        YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS: '168',
      }),
      168,
    );
    assert.throws(
      () => youtubeMembershipSnapshotMaxAgeHours({
        YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS: '0',
      }),
      YouTubeMembershipSnapshotError,
    );
  });
});
