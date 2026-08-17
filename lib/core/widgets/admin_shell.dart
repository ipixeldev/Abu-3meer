// Admin shell with responsive sidebar navigation.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/index.dart';
import '../navigation/routes.dart';

/// Admin shell — separate from main app shell.
// ignore: library_private_types_in_public_api
class AdminShell extends StatefulWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _railAnimationController;
  late final Animation<double> _railAnimation;
  bool _isRailExtended = true; // Default expanded on desktop

  @override
  void initState() {
    super.initState();
    _railAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _railAnimation = CurvedAnimation(
      parent: _railAnimationController,
      curve: Curves.easeInOut,
    );
    _railAnimationController.value = 1.0; // Start expanded
  }

  @override
  void dispose() {
    _railAnimationController.dispose();
    super.dispose();
  }

  void _toggleRail() {
    setState(() {
      _isRailExtended = !_isRailExtended;
      if (_isRailExtended) {
        _railAnimationController.forward();
      } else {
        _railAnimationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= AppSpacing.bpDesktop;
        final isTablet =
            constraints.maxWidth >= AppSpacing.bpTablet &&
            constraints.maxWidth < AppSpacing.bpDesktop;

        if (isDesktop) {
          return _buildDesktopShell(context);
        } else if (isTablet) {
          return _buildTabletShell(context);
        } else {
          return _buildMobileShell(context);
        }
      },
    );
  }

  Widget _buildDesktopShell(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _getCurrentAdminIndex(location);
    final items = _getAdminNavItems(context);

    return Row(
      children: [
        // Navigation Rail
        AnimatedBuilder(
          animation: _railAnimation,
          builder: (context, _) {
            final railWidth = lerpDouble(72, 280, _railAnimation.value)!;
            return Container(
              width: railWidth,
              color: AppColors.bgSurface,
              child: Column(
                children: [
                  // Header
                  _buildRailHeader(context),

                  // Divider
                  Divider(height: 1, color: AppColors.divider),

                  // Navigation destinations
                  Expanded(
                    child: NavigationRail(
                      extended: _isRailExtended,
                      minExtendedWidth: 280,
                      backgroundColor: Colors.transparent,
                      indicatorColor: AppColors.accentPrimary.withValues(
                        alpha: 0.15,
                      ),
                      selectedIconTheme: IconThemeData(
                        color: AppColors.accentPrimary,
                        size: 22,
                      ),
                      unselectedIconTheme: IconThemeData(
                        color: AppColors.textMuted,
                        size: 22,
                      ),
                      selectedLabelTextStyle: AppTextStyles.labelMedium(
                        color: AppColors.accentPrimary,
                      ),
                      unselectedLabelTextStyle: AppTextStyles.labelMedium(
                        color: AppColors.textMuted,
                      ),
                      labelType: _isRailExtended
                          ? NavigationRailLabelType.all
                          : NavigationRailLabelType.none,
                      leading: const SizedBox.shrink(), // Header handled above
                      trailing: _buildRailFooter(context),
                      onDestinationSelected: (index) =>
                          _onAdminNavTap(context, index),
                      selectedIndex: currentIndex,
                      destinations: items
                          .map(
                            (item) => NavigationRailDestination(
                              icon: Icon(item.icon),
                              selectedIcon: Icon(item.activeIcon),
                              label: Text(item.label),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // Vertical divider
        VerticalDivider(width: 1, thickness: 1, color: AppColors.divider),

        // Main content
        Expanded(child: widget.child),
      ],
    );
  }

  Widget _buildTabletShell(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _getCurrentAdminIndex(location);
    final items = _getAdminNavItems(context);

    return Scaffold(
      body: Row(
        children: [
          // Collapsible rail on tablet
          AnimatedBuilder(
            animation: _railAnimation,
            builder: (context, _) {
              final railWidth = lerpDouble(64, 240, _railAnimation.value)!;
              return Container(
                width: railWidth,
                color: AppColors.bgSurface,
                child: Column(
                  children: [
                    _buildRailHeader(context),
                    Divider(height: 1, color: AppColors.divider),
                    Expanded(
                      child: NavigationRail(
                        extended: _isRailExtended,
                        minExtendedWidth: 240,
                        backgroundColor: Colors.transparent,
                        indicatorColor: AppColors.accentPrimary.withValues(
                          alpha: 0.15,
                        ),
                        selectedIconTheme: IconThemeData(
                          color: AppColors.accentPrimary,
                          size: 22,
                        ),
                        unselectedIconTheme: IconThemeData(
                          color: AppColors.textMuted,
                          size: 22,
                        ),
                        selectedLabelTextStyle: AppTextStyles.labelSmall(
                          color: AppColors.accentPrimary,
                        ),
                        unselectedLabelTextStyle: AppTextStyles.labelSmall(
                          color: AppColors.textMuted,
                        ),
                        labelType: _isRailExtended
                            ? NavigationRailLabelType.all
                            : NavigationRailLabelType.none,
                        trailing: _buildRailFooter(context),
                        onDestinationSelected: (index) =>
                            _onAdminNavTap(context, index),
                        selectedIndex: currentIndex,
                        destinations: items
                            .map(
                              (item) => NavigationRailDestination(
                                icon: Icon(item.icon),
                                selectedIcon: Icon(item.activeIcon),
                                label: Text(item.label),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          VerticalDivider(width: 1, thickness: 1, color: AppColors.divider),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildMobileShell(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _getCurrentAdminIndex(location);
    final items = _getAdminNavItems(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Admin', style: AppTextStyles.headlineSmall()),
        leading: IconButton(
          icon: Icon(
            _isRailExtended ? Icons.menu_open : Icons.menu,
            color: AppColors.textPrimary,
          ),
          onPressed: _toggleRail,
        ),
      ),
      body: Row(
        children: [
          // Overlay drawer on mobile
          AnimatedBuilder(
            animation: _railAnimation,
            builder: (context, _) {
              final drawerWidth = lerpDouble(0.0, 280.0, _railAnimation.value)!;
              if (drawerWidth == 0) return const SizedBox.shrink();

              return SizedBox(
                width: drawerWidth,
                child: Container(
                  color: AppColors.bgSurface,
                  child: Column(
                    children: [
                      _buildRailHeader(context),
                      Divider(height: 1, color: AppColors.divider),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            for (int i = 0; i < items.length; i++)
                              _buildMobileNavItem(
                                context,
                                items[i],
                                i,
                                currentIndex,
                              ),
                          ],
                        ),
                      ),
                      _buildRailFooter(context),
                    ],
                  ),
                ),
              );
            },
          ),
          // Content
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildMobileNavItem(
    BuildContext context,
    _AdminNavItem item,
    int index,
    int currentIndex,
  ) {
    final isSelected = index == currentIndex;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _onAdminNavTap(context, index);
          _toggleRail(); // Close drawer on mobile
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.accentPrimary.withValues(alpha: 0.15)
                : Colors.transparent,
            border: Border(
              left: isSelected
                  ? BorderSide(color: AppColors.accentPrimary, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? item.activeIcon : item.icon,
                size: 22,
                color: isSelected
                    ? AppColors.accentPrimary
                    : AppColors.textMuted,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                item.label,
                style: AppTextStyles.labelMedium(
                  color: isSelected
                      ? AppColors.accentPrimary
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRailHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        children: [
          // Admin badge + title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Text(
              'ADMIN',
              style: AppTextStyles.labelSmall(color: AppColors.error),
            ),
          ),
          if (_isRailExtended) ...[
            const SizedBox(width: AppSpacing.sm),
            Text('Fan League', style: AppTextStyles.headlineSmall()),
          ],
          const Spacer(),
          // Collapse/Expand button
          IconButton(
            icon: Icon(
              _isRailExtended ? Icons.chevron_left : Icons.chevron_right,
              color: AppColors.textMuted,
            ),
            onPressed: _toggleRail,
            tooltip: _isRailExtended ? 'Collapse' : 'Expand',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildRailFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(color: AppColors.divider),
          const SizedBox(height: AppSpacing.sm),
          // Quick stats
          Consumer<AppState>(
            builder: (context, state, _) {
              return Column(
                children: [
                  _AdminStatRow(
                    label: 'Users',
                    value: state.allUsers.length.toString(),
                    icon: Icons.people_outline,
                  ),
                  _AdminStatRow(
                    label: 'Active Today',
                    value: state.mockAdminAnalytics.activeToday.toString(),
                    icon: Icons.trending_up,
                  ),
                  _AdminStatRow(
                    label: 'Predictions Today',
                    value: state.mockAdminAnalytics.predictionsToday.toString(),
                    icon: Icons.sports_soccer,
                  ),
                  _AdminStatRow(
                    label: 'XP Distributed',
                    value: _formatNumber(
                      state.mockAdminAnalytics.totalXpDistributed,
                    ),
                    icon: Icons.star_outline,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  List<_AdminNavItem> _getAdminNavItems(BuildContext context) => [
    _AdminNavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Overview',
      route: AppRoutes.adminOverview,
    ),
    _AdminNavItem(
      icon: Icons.sports_soccer_outlined,
      activeIcon: Icons.sports_soccer,
      label: 'Matches',
      route: AppRoutes.adminMatches,
    ),
    _AdminNavItem(
      icon: Icons.quiz_outlined,
      activeIcon: Icons.quiz,
      label: 'Predictions',
      route: AppRoutes.adminPredictions,
    ),
    _AdminNavItem(
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment,
      label: 'Challenges',
      route: AppRoutes.adminChallenges,
    ),
    _AdminNavItem(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Users',
      route: AppRoutes.adminUsers,
    ),
    _AdminNavItem(
      icon: Icons.flag_outlined,
      activeIcon: Icons.flag,
      label: 'Suspicious Activity',
      route: AppRoutes.adminSuspicious,
    ),
    _AdminNavItem(
      icon: Icons.card_giftcard_outlined,
      activeIcon: Icons.card_giftcard,
      label: 'Rewards',
      route: AppRoutes.adminRewards,
    ),
    _AdminNavItem(
      icon: Icons.emoji_events_outlined,
      activeIcon: Icons.emoji_events,
      label: 'Achievements',
      route: AppRoutes.adminAchievements,
    ),
    _AdminNavItem(
      icon: Icons.leaderboard_outlined,
      activeIcon: Icons.leaderboard,
      label: 'Leaderboards',
      route: AppRoutes.adminLeaderboards,
    ),
    _AdminNavItem(
      icon: Icons.attach_money_outlined,
      activeIcon: Icons.attach_money,
      label: 'Points',
      route: AppRoutes.adminPoints,
    ),
    _AdminNavItem(
      icon: Icons.analytics_outlined,
      activeIcon: Icons.analytics,
      label: 'Statistics',
      route: AppRoutes.adminStatistics,
    ),
    _AdminNavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Settings',
      route: AppRoutes.adminSettings,
    ),
  ];

  int _getCurrentAdminIndex(String location) {
    final items = _getAdminNavItems(context);
    for (int i = 0; i < items.length; i++) {
      if (location.startsWith(items[i].route)) {
        return i;
      }
    }
    // Special cases
    if (location.startsWith('/admin/matches/')) return 1;
    if (location.startsWith('/admin/challenges/')) return 3;
    if (location.startsWith('/admin/users/')) return 4;
    return 0;
  }

  void _onAdminNavTap(BuildContext context, int index) {
    final items = _getAdminNavItems(context);
    if (index < items.length) {
      context.go(items[index].route);
    }
  }
}

class _AdminNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;

  const _AdminNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });
}

class _AdminStatRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _AdminStatRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTextStyles.labelSmall())),
          Text(
            value,
            style: AppTextStyles.numberSmall(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
