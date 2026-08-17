// Main responsive shell for the user app.
// Mobile: bottom navigation bar
// Tablet: bottom navigation bar
// Desktop: left sidebar navigation

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/index.dart';
import '../navigation/routes.dart';

class MainShell extends StatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _railAnimationController;
  late final Animation<double> _railAnimation;
  bool _isRailExtended = false;

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
        } else {
          return _buildMobileShell(context, isTablet: isTablet);
        }
      },
    );
  }

  Widget _buildMobileShell(BuildContext context, {required bool isTablet}) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _getCurrentIndex(location);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: _buildBottomNavBar(context, currentIndex, isTablet),
    );
  }

  Widget _buildBottomNavBar(
    BuildContext context,
    int currentIndex,
    bool isTablet,
  ) {
    final items = _getNavItems(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        boxShadow: AppSpacing.shadowMd,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? AppSpacing.xl : AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = index == currentIndex;

              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _onNavTap(context, index),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                        horizontal: isTablet ? AppSpacing.md : AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.accentPrimary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusLg,
                        ),
                        border: isSelected
                            ? Border.all(
                                color: AppColors.accentPrimary,
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? item.activeIcon : item.icon,
                            size: isTablet ? 26 : 24,
                            color: isSelected
                                ? AppColors.accentPrimary
                                : AppColors.textMuted,
                          ),
                          if (isTablet) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              item.label,
                              style: AppTextStyles.labelSmall(
                                color: isSelected
                                    ? AppColors.accentPrimary
                                    : AppColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopShell(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _getCurrentIndex(location);
    final items = _getNavItems(context);

    return Row(
      children: [
        // Navigation Rail
        AnimatedBuilder(
          animation: _railAnimation,
          builder: (context, _) {
            final railWidth = lerpDouble(72, 240, _railAnimation.value)!;
            return SizedBox(
              width: railWidth,
              child: NavigationRail(
                extended: _isRailExtended,
                minExtendedWidth: 240,
                backgroundColor: AppColors.bgSurface,
                indicatorColor: AppColors.accentPrimary.withValues(alpha: 0.15),
                selectedIconTheme: IconThemeData(
                  color: AppColors.accentPrimary,
                  size: 24,
                ),
                unselectedIconTheme: IconThemeData(
                  color: AppColors.textMuted,
                  size: 24,
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
                leading: _buildRailHeader(context),
                trailing: _buildRailFooter(context),
                onDestinationSelected: (index) => _onNavTap(context, index),
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

  Widget _buildRailHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        children: [
          // Logo/Name
          Text(
            'FAN LEAGUE',
            style: AppTextStyles.titleSmall(color: AppColors.accentPrimary),
          ),
          const Spacer(),
          // Collapse/Expand button
          IconButton(
            icon: Icon(
              _isRailExtended ? Icons.chevron_left : Icons.chevron_right,
              color: AppColors.textMuted,
            ),
            onPressed: _toggleRail,
            tooltip: _isRailExtended ? 'Collapse' : 'Expand',
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
          // User avatar + name (compact)
          if (_isRailExtended)
            Consumer<AppState>(
              builder: (context, state, _) {
                if (!state.isAuthenticated || state.currentUser == null) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.bgSurfaceElevated,
                      child: Text(
                        state.currentUser!.displayName.isNotEmpty
                            ? state.currentUser!.displayName[0].toUpperCase()
                            : state.currentUser!.username[0].toUpperCase(),
                        style: AppTextStyles.numberSmall(
                          color: AppColors.accentPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      state.currentUser!.displayName,
                      style: AppTextStyles.labelSmall(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${state.currentUser!.username}',
                      style: AppTextStyles.labelSmall(
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // XP mini bar
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: state.currentUser!.levelProgress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.accentPrimary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'L${state.currentUser!.level} • ${state.currentUser!.xp} XP',
                      style: AppTextStyles.labelSmall(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  List<_NavItem> _getNavItems(BuildContext context) => [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: AppRoutes.home,
    ),
    _NavItem(
      icon: Icons.sports_soccer_outlined,
      activeIcon: Icons.sports_soccer,
      label: 'Predict',
      route: AppRoutes.matchCenter('mtc_clasico_2024_08_24'),
    ),
    _NavItem(
      icon: Icons.leaderboard_outlined,
      activeIcon: Icons.leaderboard,
      label: 'League',
      route: AppRoutes.league,
    ),
    _NavItem(
      icon: Icons.flag_outlined,
      activeIcon: Icons.flag,
      label: 'Fan War',
      route: AppRoutes.fanWar,
    ),
    _NavItem(
      icon: Icons.quiz_outlined,
      activeIcon: Icons.quiz,
      label: 'Challenges',
      route: AppRoutes.challenges,
    ),
    _NavItem(
      icon: Icons.local_fire_department_outlined,
      activeIcon: Icons.local_fire_department,
      label: 'Streak',
      route: AppRoutes.streak,
    ),
    _NavItem(
      icon: Icons.emoji_events_outlined,
      activeIcon: Icons.emoji_events,
      label: 'Achievements',
      route: AppRoutes.achievements,
    ),
    _NavItem(
      icon: Icons.star_outline,
      activeIcon: Icons.star,
      label: 'Levels',
      route: AppRoutes.levels,
    ),
    _NavItem(
      icon: Icons.card_giftcard_outlined,
      activeIcon: Icons.card_giftcard,
      label: 'Rewards',
      route: AppRoutes.loyalty,
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: AppRoutes.profile,
    ),
  ];

  int _getCurrentIndex(String location) {
    final items = _getNavItems(context);
    for (int i = 0; i < items.length; i++) {
      if (location.startsWith(items[i].route)) {
        return i;
      }
    }
    // Special cases
    if (location.startsWith('/match/')) return 1; // Predict tab
    if (location.startsWith('/challenges/')) return 4;
    if (location.startsWith('/achievements/')) return 6;
    if (location.startsWith('/loyalty/')) return 8;
    if (location.startsWith('/profile/')) return 9;
    return 0;
  }

  void _onNavTap(BuildContext context, int index) {
    final items = _getNavItems(context);
    if (index < items.length) {
      context.go(items[index].route);
    }
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });
}
