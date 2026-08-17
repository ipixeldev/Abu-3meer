# Football data and asset plan

## Recommended demo path

Keep the bundled mock match data as the reliable presentation fallback. For
fresh fixtures, tables, teams, and crests, add a small server-side proxy in the
next backend phase. Never ship a paid football-data token in the Flutter web
bundle because browser source and network requests expose it.

### Primary API: football-data.org

- Good fit for fixtures, results, competition tables, team metadata, and crest
  URLs.
- Uses API v4 and an `X-Auth-Token` header.
- A sensible first integration for the client demo because the resource model
  is comparatively small and documented.
- Documentation: https://www.football-data.org/documentation/quickstart

### Rich/live alternative: SoccerFootball.info

- Suitable if the product later needs richer match payloads, live events,
  odds, xG, or WebSocket updates.
- Direct access uses a token query parameter; RapidAPI access uses headers.
- Its Basic plan currently offers 200 free requests and then pay-per-use with a
  low hourly limit, so it is not a zero-cost anonymous public feed.
- Documentation: https://info.soccerfootball.info/readme
- Pricing: https://info.soccerfootball.info/price-and-limits

## Images and team marks

- Use Wikimedia Commons only after checking each file page and preserving its
  exact attribution/license. Bundled demo images are listed in
  `assets/ATTRIBUTION.md`.
- Football API crest URLs may be useful for a private demo, but production use
  still requires checking the API's media terms and each club's trademark
  rights.
- The current UI deliberately keeps original vector-style badges instead of
  bundling official club logos. Replace them only after the client confirms
  licensing/brand permission.

## Backend shape for the real project

1. A scheduled Firebase Function fetches upcoming fixtures and standings.
2. Firestore stores normalized competitions, teams, matches, and trivia packs.
3. Flutter reads the cached documents; it never calls the provider with a
   private token.
4. The admin console triggers an on-demand refresh and edits trivia questions.
5. The bundled mock repository remains available as an offline/demo fallback.
