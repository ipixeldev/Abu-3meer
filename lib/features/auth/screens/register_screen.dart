// Multi-step Registration / Onboarding Screen.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/index.dart';
import '../../core/state/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/models/user.dart';
import '../../core/navigation/routes.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/cards.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // Form controllers
  // Step 1: Account
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Step 2: Profile
  final _displayNameController = TextEditingController();
  String _selectedCountry = 'SE';
  String? _avatarUrl;

  // Step 3: Team (handled in separate screen)

  final List<String> _countries = [
    'SE', 'ES', 'GB', 'US', 'DE', 'FR', 'IT', 'BR', 'AR', 'MX',
    'QA', 'AE', 'EG', 'IN', 'CN', 'JP', 'AU', 'CA', 'PT', 'NL',
    'BE', 'PL', 'TR', 'SA', 'NG', 'ZA', 'FR', 'NO', 'DK', 'FI',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_validateCurrentPage()) {
      if (_currentPage < 2) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        _submitRegistration();
      }
    }
  }

  void _previousPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  bool _validateCurrentPage() {
    setState(() => _errorMessage = null);

    switch (_currentPage) {
      case 0: // Account
        if (_usernameController.text.trim().length < 3) {
          setState(() => _errorMessage = 'Username must be at least 3 characters');
          return false;
        }
        if (_emailController.text.trim().isEmpty || !_emailController.text.contains('@')) {
          setState(() => _errorMessage = 'Enter a valid email');
          return false;
        }
        if (_passwordController.text.length < 8) {
          setState(() => _errorMessage = 'Password must be at least 8 characters');
          return false;
        }
        if (_passwordController.text != _confirmPasswordController.text) {
          setState(() => _errorMessage = 'Passwords do not match');
          return false;
        }
        return true;

      case 1: // Profile
        if (_displayNameController.text.trim().isEmpty) {
          setState(() => _errorMessage = 'Display name is required');
          return false;
        }
        return true;

      case 2: // Team (handled in onboarding screen)
        return true;

      default:
        return true;
    }
  }

  Future<void> _submitRegistration() async {
    setState(() => _isLoading = true);

    final data = RegistrationData(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      confirmPassword: _confirmPasswordController.text,
      displayName: _displayNameController.text.trim(),
      countryCode: _selectedCountry,
      avatarUrl: _avatarUrl,
      team: Team.barcelona, // Will be overridden by team selection screen
    );

    final success = await context.appStateRead.register(data);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        // Navigate to team selection
        context.go(AppRoutes.onboardingTeam);
      } else {
        setState(() => _errorMessage = context.appStateRead.authError);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildAccountStep(context),
      _buildProfileStep(context),
    ];

    return Scaffold(
      backgroundColor: AppColors.bgCanvas,
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            _buildProgressIndicator(context),

            // Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: pages,
              ),
            ),

            // Navigation buttons
            _buildNavigationButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPaddingLg),
      child: Column(
        children: [
          Row(
            children: [
              for (int i = 0; i < 3; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 4,
                    margin: EdgeInsets.only(right: i < 2 ? AppSpacing.sm : 0),
                    decoration: BoxDecoration(
                      color: i <= _currentPage
                          ? AppColors.accentPrimary
                          : AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ProgressStep(label: 'Account', number: 1, active: _currentPage >= 0),
                _ProgressStep(label: 'Profile', number: 2, active: _currentPage >= 1),
                _ProgressStep(label: 'Team', number: 3, active: _currentPage >= 2),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountStep(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPaddingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Create Your Account', style: AppTextStyles.headlineMedium()),
          const SizedBox(height: AppSpacing.xs),
          Text('Enter your details to get started', style: AppTextStyles.bodyMedium()),

          const SizedBox(height: AppSpacing.xl),

          if (_errorMessage != null && _currentPage == 0)
            _buildErrorBanner(),

          // Username
          TextFormField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Username',
              hintText: 'your_username',
              prefixIcon: Icon(Icons.person_outline),
              helperText: 'At least 3 characters, unique',
            ),
            validator: (v) => v != null && v.length >= 3 ? null : 'Min 3 characters',
          ),

          const SizedBox(height: AppSpacing.md),

          // Email
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) => v != null && v.contains('@') ? null : 'Valid email required',
          ),

          const SizedBox(height: AppSpacing.md),

          // Password
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: '••••••••',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textMuted),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              helperText: 'At least 8 characters',
            ),
            validator: (v) => v != null && v.length >= 8 ? null : 'Min 8 characters',
          ),

          const SizedBox(height: AppSpacing.md),

          // Confirm Password
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _nextPage(),
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              hintText: '••••••••',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textMuted),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            validator: (v) => v == _passwordController.text ? null : 'Passwords must match',
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStep(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPaddingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set Up Your Profile', style: AppTextStyles.headlineMedium()),
          const SizedBox(height: AppSpacing.xs),
          Text('This is how other fans will see you', style: AppTextStyles.bodyMedium()),

          const SizedBox(height: AppSpacing.xl),

          if (_errorMessage != null && _currentPage == 1)
            _buildErrorBanner(),

          // Avatar placeholder
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: AppColors.bgSurfaceElevated,
                  child: Text(
                    _displayNameController.text.isNotEmpty
                        ? _displayNameController.text[0].toUpperCase()
                        : '?',
                    style: AppTextStyles.numberDisplay(size: 40, color: AppColors.accentPrimary),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.accentPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.camera_alt, size: 18, color: AppColors.textOnAccent),
                      onPressed: () {
                        // Demo: just show snackbar
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Demo: Avatar upload not implemented')),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Display Name
          TextFormField(
            controller: _displayNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              hintText: 'How fans see you',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: (v) => v != null && v.isNotEmpty ? null : 'Required',
            onChanged: (_) => setState(() {}), // Update avatar initial
          ),

          const SizedBox(height: AppSpacing.md),

          // Country
          DropdownButtonFormField<String>(
            value: _selectedCountry,
            decoration: const InputDecoration(
              labelText: 'Country',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
            items: _countries.map((code) {
              final flag = _countryFlag(code);
              return DropdownMenuItem(
                value: code,
                child: Row(
                  children: [
                    Text(flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(code),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedCountry = v!),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(_errorMessage!, style: AppTextStyles.bodySmall(color: AppColors.error))),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPaddingLg),
      child: Row(
        children: [
          if (_currentPage > 0)
            Expanded(
              child: SecondaryButton(
                label: 'Back',
                onPressed: _previousPage,
                fullWidth: true,
              ),
            )
          else
            const Expanded(child: SizedBox.shrink()),

          if (_currentPage > 0) const SizedBox(width: AppSpacing.md),

          Expanded(
            flex: 2,
            child: PrimaryButton(
              label: _currentPage == 1 ? 'Continue to Team Selection' : 'Continue',
              onPressed: _nextPage,
              loading: _isLoading,
              fullWidth: true,
              height: 56,
            ),
          ),
        ],
      ),
    );
  }

  String _countryFlag(String code) {
    if (code.length != 2) return '🏳️';
    final offset = 0x1F1E6 - 0x41;
    return String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => c + offset));
  }
}

class _ProgressStep extends StatelessWidget {
  final String label;
  final int number;
  final bool active;

  const _ProgressStep({
    required this.label,
    required this.number,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? AppColors.accentPrimary : AppColors.bgSurfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? AppColors.accentPrimary : AppColors.divider,
              width: 2,
            ),
          ),
          child: Center(
            child: active
                ? Icon(Icons.check, size: 16, color: AppColors.textOnAccent)
                : Text('$number', style: AppTextStyles.numberSmall(color: active ? AppColors.textOnAccent : AppColors.textMuted)),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: AppTextStyles.labelSmall(color: active ? AppColors.textPrimary : AppColors.textMuted)),
      ],
    );
  }
}
