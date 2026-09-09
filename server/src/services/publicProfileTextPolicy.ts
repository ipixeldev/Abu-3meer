export const unsafePublicProfileTextError = Object.freeze({
  error: 'UnsafePublicProfileText',
  message:
    'Choose a different username or display name. Links, contact details, and offensive language are not allowed.',
});

export type PublicProfileTextViolation =
  | 'control_characters'
  | 'contact_details'
  | 'contact_solicitation'
  | 'offensive_language';

const controlOrFormatCharacters = /[\p{Cc}\p{Cf}]/u;
const emailAddress = /[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[a-z]{2,24}/iu;
const webAddress = /(?:https?:\/\/|www\.|(?:[\p{L}\p{N}](?:[\p{L}\p{N}-]{0,61}[\p{L}\p{N}])?\.)+(?:[\p{L}]{2,63}|xn--[a-z0-9-]{2,59})(?![\p{L}\p{N}-]))/iu;
const phoneNumber = /(?:\+?\d[\s().-]*){7,}/u;
const socialHandle = /(?:^|\s)@[a-z0-9_]{2,30}(?:\s|$)/iu;
const contactRequest = /(?:^|\s)(?:contact|dm|message|pm)\s+(?:me|us)(?:\s|$)/iu;

const contactServiceTokens = new Set([
  'discord',
  'instagram',
  'kik',
  'signal',
  'snapchat',
  'telegram',
  'tiktok',
  'viber',
  'wechat',
  'whatsapp',
  'ديسكورد',
  'سناب',
  'سنابشات',
  'سيغنال',
  'تلجرام',
  'تلغرام',
  'تيليجرام',
  'تيك توك',
  'تيكتوك',
  'فايبر',
  'واتس',
  'واتساب',
]);

const offensiveTokens = new Set([
  'bitch',
  'bitches',
  'cunt',
  'cunts',
  'fag',
  'faggot',
  'faggots',
  'fuck',
  'fucked',
  'fucker',
  'fuckers',
  'fucking',
  'kys',
  'nazi',
  'nazis',
  'nigga',
  'niggas',
  'nigger',
  'niggers',
  'pedo',
  'pedophile',
  'porn',
  'porno',
  'rape',
  'rapist',
  'retard',
  'retarded',
  'sex',
  'slut',
  'sluts',
  'whore',
  'whores',
  'xxx',
  'خرا',
  'خول',
  'زب',
  'شرموط',
  'شرموطه',
  'طيز',
  'قحبه',
  'كس',
  'منيوك',
  'نيك',
]);

const offensivePhrases = new Set([
  'fuck you',
  'go kill yourself',
  'kill yourself',
  'ابن الكلب',
  'اقتل نفسك',
  'كس امك',
]);

const contactPhrases = new Set([
  'contact me',
  'contact us',
  'dm me',
  'message me',
  'pm me',
  'ارسل لي',
  'تواصل معي',
  'راسلني',
  'كلمني خاص',
]);

const separatorEvasionPatterns = [
  /(?:^|[^a-z0-9])f[^a-z0-9]*u[^a-z0-9]*c[^a-z0-9]*k(?:[^a-z0-9]|$)/u,
  /(?:^|[^a-z0-9])n[^a-z0-9]*i[^a-z0-9]*g[^a-z0-9]*g[^a-z0-9]*(?:a|e)[^a-z0-9]*r?(?:[^a-z0-9]|$)/u,
  /(?:^|[^a-z0-9])p[^a-z0-9]*o[^a-z0-9]*r[^a-z0-9]*n(?:[^a-z0-9]|$)/u,
];

function canonicalText(value: string): string {
  return value
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[\u0640\u064b-\u065f\u0670\u06d6-\u06ed]/gu, '')
    .replace(/[أإآٱ]/gu, 'ا')
    .replace(/ة/gu, 'ه')
    .replace(/ى/gu, 'ي');
}

function leetspeakFold(value: string): string {
  return value
    .replace(/0/gu, 'o')
    .replace(/1/gu, 'i')
    .replace(/3/gu, 'e')
    .replace(/4/gu, 'a')
    .replace(/5/gu, 's')
    .replace(/7/gu, 't')
    .replace(/\$/gu, 's');
}

function wordTokens(value: string): string[] {
  return value.match(/[\p{L}\p{N}]+/gu) ?? [];
}

function containsPhrase(tokens: string[], phrases: Set<string>): boolean {
  const padded = ` ${tokens.join(' ')} `;
  for (const phrase of phrases) {
    if (padded.includes(` ${phrase} `)) return true;
  }
  return false;
}

/**
 * Conservative local filter for public, user-selected identity text. It does
 * not attempt to classify images or private text and never returns the input,
 * which lets callers reject a value without putting it into logs.
 */
export function publicProfileTextViolation(
  value: string,
): PublicProfileTextViolation | null {
  if (controlOrFormatCharacters.test(value)) return 'control_characters';

  const canonical = canonicalText(value);
  if (
    emailAddress.test(canonical)
    || webAddress.test(canonical)
    || phoneNumber.test(canonical)
    || socialHandle.test(canonical)
  ) {
    return 'contact_details';
  }

  const folded = leetspeakFold(canonical);
  const tokens = wordTokens(folded);
  if (
    contactRequest.test(folded)
    || tokens.some(token => contactServiceTokens.has(token))
    || containsPhrase(tokens, contactPhrases)
  ) {
    return 'contact_solicitation';
  }
  if (
    tokens.some(token => offensiveTokens.has(token))
    || containsPhrase(tokens, offensivePhrases)
    || separatorEvasionPatterns.some(pattern => pattern.test(folded))
  ) {
    return 'offensive_language';
  }
  return null;
}

export function isPublicProfileTextAllowed(value: string): boolean {
  return publicProfileTextViolation(value) == null;
}

/**
 * OAuth/Firebase identity text is not chosen inside our onboarding form. If it
 * is unsafe or outside the database limit, publish a neutral server-generated
 * name so sign-in still succeeds and the user can choose an allowed name.
 */
export function safeInitialDisplayName(
  candidate: unknown,
  fallback: string,
): string {
  if (typeof candidate !== 'string') return fallback;
  const trimmed = candidate.trim();
  if (
    trimmed.length < 2
    || trimmed.length > 100
    || !isPublicProfileTextAllowed(trimmed)
  ) {
    return fallback;
  }
  return trimmed;
}
