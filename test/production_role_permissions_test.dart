import 'package:abu_3meer/production/models.dart';
import 'package:flutter_test/flutter_test.dart';

AbuUserProfile profileWithRole(String role) => AbuUserProfile(
  uid: 'uid-$role',
  email: '$role@example.com',
  username: role,
  displayName: role,
  country: 'Morocco',
  supportedTeam: 'Barcelona',
  avatarUrl: '',
  role: role,
  membershipMultiplier: role == 'member' ? 2 : 1,
  totalPoints: 0,
  monthlyPoints: 0,
  seasonPoints: 0,
  suspended: false,
);

void main() {
  test('paid membership unlocks member access without claiming CSV ownership or staff roles', () {
    const profile = AbuUserProfile(
      uid: 'firebase-user',
      backendUserId: 'database-user',
      email: 'fan@example.com',
      username: 'fan',
      displayName: 'Fan',
      country: 'Sweden',
      supportedTeam: 'Barcelona',
      avatarUrl: '',
      role: 'fan',
      membershipMultiplier: 1,
      isProSubscriber: true,
      totalPoints: 0,
      monthlyPoints: 0,
      seasonPoints: 0,
      suspended: false,
    );
    expect(profile.hasMemberAccess, true);
    expect(profile.isYouTubeMember, false);
    expect(profile.isAdmin, false);
    expect(profile.canUploadMembershipSnapshot, false);
    final edited = profile.copyWith(displayName: 'Edited fan');
    expect(edited.isProSubscriber, true);
    expect(edited.backendUserId, 'database-user');
    expect(edited.hasMemberAccess, true);
  });
  test('super admin has content, CSV upload, and role-management access', () {
    final profile = profileWithRole('superAdmin');

    expect(profile.isAdmin, isTrue);
    expect(profile.canManageContent, isTrue);
    expect(profile.canUploadMembershipSnapshot, isTrue);
    expect(profile.canManageRoles, isTrue);
  });

  test('admin has content and CSV upload access but cannot manage roles', () {
    final profile = profileWithRole('admin');

    expect(profile.isAdmin, isTrue);
    expect(profile.canManageContent, isTrue);
    expect(profile.canUploadMembershipSnapshot, isTrue);
    expect(profile.canManageRoles, isFalse);
  });

  test('moderator can upload CSV without Admin Studio content access', () {
    final profile = profileWithRole('moderator');

    expect(profile.isAdmin, isFalse);
    expect(profile.canManageContent, isFalse);
    expect(profile.canModerate, isTrue);
    expect(profile.canUploadMembershipSnapshot, isTrue);
    expect(profile.canManageRoles, isFalse);
  });

  test('member and fan permissions are unchanged', () {
    for (final role in ['member', 'fan']) {
      final profile = profileWithRole(role);
      expect(profile.isAdmin, isFalse, reason: role);
      expect(profile.canManageContent, isFalse, reason: role);
      expect(profile.canModerate, isFalse, reason: role);
      expect(profile.canUploadMembershipSnapshot, isFalse, reason: role);
      expect(profile.canManageRoles, isFalse, reason: role);
    }
  });
}
