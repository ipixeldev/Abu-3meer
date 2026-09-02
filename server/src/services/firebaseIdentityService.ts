/** Extract the Google provider subject already proven by Firebase Auth. */
export function googleProviderSubjectFromFirebaseIdentities(
  identities: Record<string, unknown> | undefined,
): string | null {
  const google = identities?.['google.com'];
  if (!Array.isArray(google)) return null;
  const subject = google.find(
    (value): value is string => typeof value === 'string' && value.length > 0,
  );
  return subject ?? null;
}
