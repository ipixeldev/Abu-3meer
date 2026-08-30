import 'dart:async';

import 'package:flutter/material.dart';

import '../../../production/models.dart';
import '../../../production/production_repository.dart';

/// Stable order shared by the match-centre navigation and regression tests.
const matchCenterTabOrder = <String>['facts', 'lineup', 'table'];

/// Provider-backed match centre. Empty provider sections remain honest empty
/// states; the UI never invents scorers, cards, players, or statistics.
class MatchFactsScreen extends StatefulWidget {
  const MatchFactsScreen({
    super.key,
    required this.event,
    required this.repository,
  });

  final MatchEvent event;
  final ProductionRepository repository;

  @override
  State<MatchFactsScreen> createState() => _MatchFactsScreenState();
}

class _MatchFactsScreenState extends State<MatchFactsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  MatchDetails _details = const MatchDetails();
  Timer? _refreshTimer;
  bool _loading = true;
  String? _error;

  bool get _arabic =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
  bool get _light => Theme.of(context).brightness == Brightness.light;
  Color get _background =>
      _light ? const Color(0xFFF4F7FC) : const Color(0xFF0A0D14);
  Color get _surface => _light ? Colors.white : const Color(0xFF101722);
  Color get _surfaceAlt =>
      _light ? const Color(0xFFEAF0FA) : const Color(0xFF171F2D);
  Color get _line => _light ? const Color(0xFFD5DEEE) : const Color(0xFF273248);
  Color get _text => _light ? const Color(0xFF101A33) : const Color(0xFFF6F8FC);
  Color get _muted =>
      _light ? const Color(0xFF677793) : const Color(0xFF91A0B7);
  Color get _accent =>
      _light ? const Color(0xFF285FD8) : const Color(0xFFC8FF38);

  String _t(String english, String arabic) => _arabic ? arabic : english;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: matchCenterTabOrder.length,
      vsync: this,
    );
    _details = MatchDetails(timeline: widget.event.timeline);
    unawaited(_loadDetails());
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // Re-evaluate the kickoff window on every tick. A screen opened more
      // than an hour before kickoff must begin polling when that window starts.
      if (_shouldPollDetails) {
        unawaited(_loadDetails(showLoading: false, forceRefresh: true));
      }
    });
  }

  bool get _shouldPollDetails {
    final status = widget.event.status.toLowerCase();
    if (status == 'live') return true;
    if (const {
      'completed',
      'finished',
      'cancelled',
      'postponed',
    }.contains(status)) {
      return false;
    }
    final now = DateTime.now();
    return now.isAfter(
          widget.event.kickoffAt.subtract(const Duration(hours: 1)),
        ) &&
        now.isBefore(widget.event.kickoffAt.add(const Duration(hours: 4)));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails({
    bool showLoading = true,
    bool forceRefresh = false,
  }) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final details = await widget.repository.fetchMatchDetails(
        widget.event,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _details = _retainPublishedSections(_details, details);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t(
          'Match details could not be refreshed.',
          'تعذر تحديث تفاصيل المباراة.',
        );
      });
    }
  }

  MatchDetails _retainPublishedSections(
    MatchDetails current,
    MatchDetails incoming,
  ) => incoming.copyWith(
    timeline: incoming.timeline.isEmpty ? current.timeline : incoming.timeline,
    lineup: incoming.lineup.isEmpty ? current.lineup : incoming.lineup,
    statistics: incoming.statistics.isEmpty
        ? current.statistics
        : incoming.statistics,
    standings: incoming.standings.isEmpty
        ? current.standings
        : incoming.standings,
    venue: incoming.venue.isEmpty ? current.venue : incoming.venue,
    season: incoming.season.isEmpty ? current.season : incoming.season,
    provider: incoming.provider.isEmpty ? current.provider : incoming.provider,
  );

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _text,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _teamBadge(event.homeTeam, event.homeLogoUrl, size: 34),
            const SizedBox(width: 10),
            Text(
              event.homeScore == null || event.awayScore == null
                  ? 'VS'
                  : '${event.homeScore}  –  ${event.awayScore}',
              style: TextStyle(
                color: _text,
                fontWeight: FontWeight.w900,
                fontSize: 17,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(width: 10),
            _teamBadge(event.awayTeam, event.awayLogoUrl, size: 34),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _t('Refresh', 'تحديث'),
            onPressed: _loading ? null : () => _loadDetails(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: _accent,
          unselectedLabelColor: _muted,
          indicatorColor: _accent,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: _t('Facts', 'الأحداث')),
            Tab(text: _t('Lineup', 'التشكيلة')),
            Tab(text: _t('Table', 'الترتيب')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_factsTab(), _lineupTab(), _tableTab()],
      ),
    );
  }

  Widget _teamBadge(String team, String logoUrl, {double size = 42}) {
    final fallback = Center(
      child: Text(
        team.trim().isEmpty ? '⚽' : team.trim()[0].toUpperCase(),
        style: TextStyle(
          color: _text,
          fontSize: size * .34,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .12),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(size * .26),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl.trim().isEmpty
          ? fallback
          : Image.network(
              logoUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }

  Widget _page(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          constraints.maxWidth >= 800 ? 28 : 16,
          20,
          constraints.maxWidth >= 800 ? 28 : 16,
          48,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _factsTab() {
    if (_loading && _details.timeline.isEmpty) return _loadingState();
    return _page([
      _scoreSummary(),
      if (_details.isProviderLimited) ...[
        const SizedBox(height: 12),
        _providerLimitNotice(),
      ],
      if (_error != null) ...[const SizedBox(height: 12), _errorCard()],
      const SizedBox(height: 20),
      _sectionTitle(_t('Match timeline', 'أحداث المباراة')),
      const SizedBox(height: 10),
      if (_details.timeline.isEmpty)
        _emptyState(
          Icons.sports_soccer_outlined,
          widget.event.kickoffAt.isAfter(DateTime.now())
              ? _t(
                  'The match has not started. Verified events will appear here after kickoff.',
                  'لم تبدأ المباراة بعد. ستظهر الأحداث الموثقة هنا بعد انطلاقها.',
                )
              : _t(
                  'No verified match events have been published yet.',
                  'لم يتم نشر أحداث موثقة للمباراة بعد.',
                ),
        )
      else
        ..._details.timeline.map(_timelineCard),
      if (_details.statistics.isNotEmpty) ...[
        const SizedBox(height: 24),
        _sectionTitle(_t('Match statistics', 'إحصائيات المباراة')),
        const SizedBox(height: 10),
        _statisticsCard(),
      ],
    ]);
  }

  Widget _statisticsCard() => _card(
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.event.homeTeam,
                textAlign: TextAlign.start,
                style: TextStyle(color: _text, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.event.awayTeam,
                textAlign: TextAlign.end,
                style: TextStyle(color: _text, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._details.statistics.map(
          (statistic) => Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    statistic.homeValue.isEmpty ? '—' : statistic.homeValue,
                    style: TextStyle(color: _text, fontWeight: FontWeight.w900),
                  ),
                ),
                Expanded(
                  child: Text(
                    statistic.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    statistic.awayValue.isEmpty ? '—' : statistic.awayValue,
                    textAlign: TextAlign.end,
                    style: TextStyle(color: _text, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _scoreSummary() {
    final event = widget.event;
    return _card(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statusPill(),
              if (_details.season.isNotEmpty) ...[
                const SizedBox(width: 8),
                _pill(_details.season, _muted),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _scoreTeam(event.homeTeam, event.homeLogoUrl)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    Text(
                      event.homeScore == null || event.awayScore == null
                          ? 'VS'
                          : '${event.homeScore} – ${event.awayScore}',
                      style: TextStyle(
                        color: _text,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (_details.venue.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(
                          _details.venue,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _muted, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: _scoreTeam(event.awayTeam, event.awayLogoUrl)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scoreTeam(String name, String logoUrl) => Column(
    children: [
      _teamBadge(name, logoUrl, size: 64),
      const SizedBox(height: 10),
      Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _text, fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _statusPill() {
    final status = widget.event.status.toLowerCase();
    final label = switch (status) {
      'live' => _t('LIVE', 'مباشر'),
      'completed' || 'finished' => _t('FULL TIME', 'انتهت'),
      'postponed' => _t('POSTPONED', 'مؤجلة'),
      _ => _t('UPCOMING', 'قادمة'),
    };
    final color = status == 'live' ? const Color(0xFFFF4365) : _accent;
    return _pill(label, color);
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .38)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w900,
        fontSize: 11,
        letterSpacing: .7,
      ),
    ),
  );

  Widget _timelineCard(MatchTimelineEvent item) {
    final typeColor = _eventColor(item.type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                item.minute.trim().isEmpty ? '—' : "${item.minute}'",
                style: TextStyle(color: typeColor, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            _eventIcon(item.type, typeColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.player.trim().isEmpty
                              ? _eventLabel(item.type)
                              : item.player,
                          style: TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (item.team.isNotEmpty)
                        Flexible(
                          child: Text(
                            item.team,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _muted, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      _eventLabel(item.type),
                      if (item.assist.isNotEmpty)
                        '${_t('Assist', 'صناعة')}: ${item.assist}',
                      if (item.detail.isNotEmpty) item.detail,
                    ].join(' · '),
                    style: TextStyle(color: _muted, height: 1.35, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineupTab() {
    if (_loading && _details.lineup.isEmpty) return _loadingState();
    final substitutions = _details.timeline
        .where((item) => item.type.toLowerCase().contains('sub'))
        .toList(growable: false);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final home = _lineupTeam(true);
    final away = _lineupTeam(false);
    return _page([
      _sectionTitle(_t('Starting XI & substitutes', 'التشكيلة والبدلاء')),
      if (_details.isProviderLimited) ...[
        const SizedBox(height: 12),
        _providerLimitNotice(),
      ],
      const SizedBox(height: 16),
      if (_details.lineup.isEmpty)
        _emptyState(
          Icons.groups_2_outlined,
          _t(
            'The data provider has not published the official lineup yet. Lineups are usually released shortly before kickoff.',
            'لم ينشر مزود البيانات التشكيلة الرسمية بعد. عادةً ما تُنشر التشكيلات قبل انطلاق المباراة بقليل.',
          ),
        )
      else if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: home),
            const SizedBox(width: 16),
            Expanded(child: away),
          ],
        )
      else ...[
        home,
        const SizedBox(height: 14),
        away,
      ],
      if (substitutions.isNotEmpty) ...[
        const SizedBox(height: 24),
        _sectionTitle(_t('Player changes', 'تغييرات اللاعبين')),
        const SizedBox(height: 10),
        ...substitutions.map(_timelineCard),
      ],
    ]);
  }

  Widget _lineupTeam(bool isHome) {
    final teamName = isHome ? widget.event.homeTeam : widget.event.awayTeam;
    final players = _details.lineup
        .where((player) => player.isHome == isHome)
        .toList(growable: false);
    final starters = players
        .where((player) => !player.isSubstitute)
        .toList(growable: false);
    final substitutes = players
        .where((player) => player.isSubstitute)
        .toList(growable: false);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            teamName,
            style: TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          _lineupGroup(_t('STARTING XI', 'التشكيلة الأساسية'), starters),
          if (substitutes.isNotEmpty) ...[
            const SizedBox(height: 18),
            _lineupGroup(_t('BENCH', 'البدلاء'), substitutes),
          ],
          if (players.isEmpty)
            Text(
              _t('No players supplied.', 'لم يتم توفير اللاعبين.'),
              style: TextStyle(color: _muted),
            ),
        ],
      ),
    );
  }

  Widget _lineupGroup(String title, List<MatchLineupPlayer> players) {
    if (players.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _accent,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        ...players.map(
          (player) => Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    player.squadNumber.isEmpty ? '—' : player.squadNumber,
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    player.player,
                    style: TextStyle(color: _text, fontWeight: FontWeight.w700),
                  ),
                ),
                if (player.position.isNotEmpty)
                  Text(
                    player.position,
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tableTab() {
    if (_loading && _details.standings.isEmpty) return _loadingState();
    return _page([
      _sectionTitle(_t('League table', 'جدول الترتيب')),
      if (_details.season.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(_details.season, style: TextStyle(color: _muted)),
      ],
      if (_details.isProviderLimited) ...[
        const SizedBox(height: 12),
        _providerLimitNotice(),
      ],
      const SizedBox(height: 16),
      if (_details.standings.isEmpty)
        _emptyState(
          Icons.table_rows_outlined,
          _t(
            'A league table is not available for this competition.',
            'جدول الترتيب غير متاح لهذه البطولة.',
          ),
        )
      else
        _standingsTable(),
    ]);
  }

  Widget _standingsTable() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      final statWidth = compact ? 27.0 : 42.0;
      final goalsWidth = compact ? 42.0 : 58.0;
      final rankWidth = compact ? 30.0 : 42.0;
      final textSize = compact ? 10.5 : 12.5;

      Widget statCell(
        String value, {
        double? width,
        FontWeight weight = FontWeight.w700,
        Color? color,
      }) => SizedBox(
        width: width ?? statWidth,
        child: Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(
            color: color ?? _text,
            fontSize: textSize,
            fontWeight: weight,
          ),
        ),
      );

      Widget tableRow(MatchStanding standing) {
        final highlighted = _isMatchTeam(standing.team);
        final goals = standing.goalsFor == null || standing.goalsAgainst == null
            ? '—'
            : '${standing.goalsFor}-${standing.goalsAgainst}';
        final difference = standing.goalDifference > 0
            ? '+${standing.goalDifference}'
            : '${standing.goalDifference}';
        final zoneColor = switch (standing.rank) {
          <= 4 => const Color(0xFF27D67A),
          5 => const Color(0xFF1264D8),
          6 => const Color(0xFF27C7E8),
          _ => Colors.transparent,
        };
        return Container(
          constraints: BoxConstraints(minHeight: compact ? 58 : 66),
          decoration: BoxDecoration(
            color: highlighted ? _accent.withValues(alpha: .09) : null,
            border: Border(top: BorderSide(color: _line.withValues(alpha: .7))),
          ),
          child: Row(
            children: [
              Container(width: 4, color: zoneColor),
              statCell('${standing.rank}', width: rankWidth),
              Expanded(
                child: Row(
                  children: [
                    _teamBadge(
                      standing.team,
                      standing.badgeUrl,
                      size: compact ? 27 : 32,
                    ),
                    SizedBox(width: compact ? 6 : 10),
                    Expanded(
                      child: Text(
                        standing.team,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _text,
                          fontSize: compact ? 11.5 : 14,
                          fontWeight: highlighted
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
              statCell('${standing.played}'),
              statCell('${standing.won}'),
              statCell('${standing.drawn}'),
              statCell('${standing.lost}'),
              statCell(goals, width: goalsWidth),
              statCell(difference),
              statCell(
                '${standing.points}',
                weight: FontWeight.w900,
                color: highlighted ? _accent : _text,
              ),
              SizedBox(width: compact ? 3 : 8),
            ],
          ),
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _surface,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              SizedBox(
                height: compact ? 46 : 52,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    statCell('#', width: rankWidth, weight: FontWeight.w900),
                    Expanded(
                      child: Text(
                        _t('TEAM', 'الفريق'),
                        style: TextStyle(
                          color: _text,
                          fontSize: textSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    statCell(_t('PL', 'ل'), weight: FontWeight.w900),
                    statCell(_t('W', 'ف'), weight: FontWeight.w900),
                    statCell(_t('D', 'ت'), weight: FontWeight.w900),
                    statCell(_t('L', 'خ'), weight: FontWeight.w900),
                    statCell('+/-', width: goalsWidth, weight: FontWeight.w900),
                    statCell(_t('GD', 'ف.أ'), weight: FontWeight.w900),
                    statCell(_t('PTS', 'ن'), weight: FontWeight.w900),
                    SizedBox(width: compact ? 3 : 8),
                  ],
                ),
              ),
              ..._details.standings.map(tableRow),
            ],
          ),
        ),
      );
    },
  );

  Widget _providerLimitNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB943).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFB943).withValues(alpha: .32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFFFB943),
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _t(
                'The public football feed shows up to 5 records in each section. Configure the server SPORTSDB_API_KEY for complete published lineups and tables.',
                'يعرض مزود كرة القدم العام حتى 5 سجلات في كل قسم. اضبط SPORTSDB_API_KEY على الخادم لعرض التشكيلات والجداول المنشورة كاملة.',
              ),
              style: TextStyle(color: _text, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFF4D62).withValues(alpha: .10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFF4D62).withValues(alpha: .3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF4D62)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(_error!, style: TextStyle(color: _text)),
        ),
        TextButton(
          onPressed: () => _loadDetails(forceRefresh: true),
          child: Text(_t('RETRY', 'إعادة')),
        ),
      ],
    ),
  );

  Widget _loadingState() =>
      Center(child: CircularProgressIndicator(color: _accent));

  Widget _emptyState(IconData icon, String message) => _card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(icon, size: 42, color: _muted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.45),
          ),
        ],
      ),
    ),
  );

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) =>
      Container(
        padding: padding ?? const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
          boxShadow: _light
              ? const [
                  BoxShadow(
                    color: Color(0x100B244F),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: child,
      );

  Widget _sectionTitle(String title) => Text(
    title,
    style: TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.w900),
  );

  bool _isMatchTeam(String team) {
    final key = team.trim().toLowerCase();
    return key == widget.event.homeTeam.trim().toLowerCase() ||
        key == widget.event.awayTeam.trim().toLowerCase();
  }

  Color _eventColor(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('red')) return const Color(0xFFFF4D62);
    if (normalized.contains('yellow')) return const Color(0xFFFFC84C);
    if (normalized.contains('sub')) return const Color(0xFF1FBF73);
    if (normalized.contains('goal')) return _accent;
    if (normalized.contains('var')) return const Color(0xFF8A6CFF);
    return _muted;
  }

  Widget _eventIcon(String type, Color color) {
    final normalized = type.toLowerCase();
    if (normalized.contains('yellow') || normalized.contains('red')) {
      return Container(
        width: 14,
        height: 19,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    final icon = normalized.contains('goal')
        ? Icons.sports_soccer_rounded
        : normalized.contains('sub')
        ? Icons.swap_vert_rounded
        : normalized.contains('var')
        ? Icons.tv_rounded
        : Icons.flag_outlined;
    return Icon(icon, color: color, size: 21);
  }

  String _eventLabel(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('yellow')) {
      return _t('Yellow card', 'بطاقة صفراء');
    }
    if (normalized.contains('red')) return _t('Red card', 'بطاقة حمراء');
    if (normalized == 'penalty_goal') {
      return _t('Penalty goal', 'هدف من ركلة جزاء');
    }
    if (normalized == 'own_goal') return _t('Own goal', 'هدف عكسي');
    if (normalized.contains('goal')) return _t('Goal', 'هدف');
    if (normalized.contains('sub')) return _t('Substitution', 'تبديل');
    if (normalized.contains('var')) return 'VAR';
    if (normalized.contains('period')) {
      return _t('Match period', 'فترة المباراة');
    }
    return _t('Match event', 'حدث المباراة');
  }
}
