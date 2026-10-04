import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? user;
  String? userName;
  bool loadingProfile = true;

  @override
  void initState() {
    super.initState();
    user = SupabaseService.currentUser;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final currentUser = SupabaseService.currentUser;
    if (currentUser == null) {
      if (mounted) {
        setState(() {
          loadingProfile = false;
        });
      }
      return;
    }

    try {
      final row = await SupabaseService.client
          .from('users')
          .select('name')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (!mounted) {
        userName = row?['name']?.toString().trim();
        loadingProfile = false;
        return;
      }

      setState(() {
        userName = row?['name']?.toString().trim();
        loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) {
        loadingProfile = false;
        return;
      }

      setState(() {
        loadingProfile = false;
      });
    }
  }

  Future<void> signOut() async {
    await SupabaseService.client.auth.signOut();
    if (mounted) {
      context.go('/auth');
    }
  }

  String getAvatarUrl() {
    final name = userName ?? user?.userMetadata?['name']?.toString() ?? user?.email ?? 'U';
    return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}';
  }

  String get displayName {
    final savedName = userName?.trim();
    if (savedName != null && savedName.isNotEmpty) {
      return savedName;
    }

    final rawName = user?.userMetadata?['name']?.toString().trim();
    if (rawName != null && rawName.isNotEmpty) {
      return rawName;
    }

    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'Anonymous User';
  }

  String get memberLabel {
    final createdAt = user?.createdAt;
    if (createdAt == null || createdAt.length < 7) {
      return 'Member';
    }

    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) {
      return 'Member';
    }

    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return 'Member since ${months[parsed.month - 1]} ${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final headerSurface = isDark ? const Color(0xFF18181B) : scheme.surface;
    final cardSurface = isDark ? const Color(0xFF202024) : scheme.surfaceContainerHigh;
    final accentSurface = isDark ? const Color(0xFF2A2022) : scheme.surfaceContainerHighest;
    final strongTextColor = isDark ? const Color(0xFFF5F5F7) : scheme.onSurface;
    final mutedTextColor = isDark ? const Color(0xFFB7B7C0) : scheme.onSurfaceVariant;
    final softBorderColor = isDark ? const Color(0xFF34343A) : scheme.outlineVariant;
    final shadowColor = Colors.black.withValues(
      alpha: isDark ? 0.26 : 0.08,
    );

    return Scaffold(
      body: SafeArea(
        child: user == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline, size: 54),
                      const SizedBox(height: 16),
                      const Text(
                        'No user signed in.',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Log in or create an account to view your profile and orders.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => context.go('/auth'),
                          child: const Text('Go to Auth'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                      decoration: BoxDecoration(
                        color: headerSurface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: softBorderColor),
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => context.pop(),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Profile',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: strongTextColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: scheme.primary.withValues(alpha: 0.35),
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 38,
                                  backgroundImage: NetworkImage(getAvatarUrl()),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: theme.textTheme.headlineSmall?.copyWith(
                                        color: strongTextColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (loadingProfile)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: scheme.primary,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    Text(
                                      user?.email ?? '',
                                      style: TextStyle(
                                        color: mutedTextColor,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accentSurface,
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: softBorderColor),
                                      ),
                                      child: Text(
                                        memberLabel,
                                        style: TextStyle(
                                          color: strongTextColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardSurface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: softBorderColor),
                        boxShadow: [
                          BoxShadow(color: shadowColor, blurRadius: 18),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Account',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: strongTextColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Manage your details, review orders, and control how HMU keeps you updated.',
                            style: TextStyle(
                              color: mutedTextColor,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Quick Actions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: strongTextColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: cardSurface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: softBorderColor),
                        boxShadow: [
                          BoxShadow(color: shadowColor, blurRadius: 18),
                        ],
                      ),
                      child: Column(
                        children: [
                          actionRow(
                            context: context,
                            icon: Icons.person_outline,
                            label: 'Edit Profile',
                            subtitle: 'Update your personal details',
                            onTap: () async {
                              await context.push('/edit-profile');
                              if (mounted) {
                                await _loadProfile();
                              }
                            },
                            strongTextColor: strongTextColor,
                            mutedTextColor: mutedTextColor,
                            accentSurface: accentSurface,
                            softBorderColor: softBorderColor,
                          ),
                          actionRow(
                            context: context,
                            icon: Icons.receipt_outlined,
                            label: 'Order History',
                            subtitle: 'Track current orders and history',
                            onTap: () => context.push('/orders'),
                            strongTextColor: strongTextColor,
                            mutedTextColor: mutedTextColor,
                            accentSurface: accentSurface,
                            softBorderColor: softBorderColor,
                          ),
                          actionRow(
                            context: context,
                            icon: Icons.notifications_outlined,
                            label: 'Notifications',
                            subtitle: 'Choose what updates you receive',
                            onTap: () => context.push('/notifications'),
                            strongTextColor: strongTextColor,
                            mutedTextColor: mutedTextColor,
                            accentSurface: accentSurface,
                            softBorderColor: softBorderColor,
                          ),
                          actionRow(
                            context: context,
                            icon: Icons.help_outline,
                            label: 'Help and Support',
                            subtitle: 'Get assistance when you need it',
                            onTap: () => context.push('/help'),
                            strongTextColor: strongTextColor,
                            mutedTextColor: mutedTextColor,
                            accentSurface: accentSurface,
                            softBorderColor: softBorderColor,
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign Out'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF2B1A1C)
                              : null,
                          foregroundColor: isDark
                              ? scheme.error.withValues(alpha: 0.95)
                              : null,
                          elevation: isDark ? 0 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget actionRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    required Color strongTextColor,
    required Color mutedTextColor,
    required Color accentSurface,
    required Color softBorderColor,
    bool isLast = false,
  }) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(0),
            bottom: Radius.circular(isLast ? 24 : 0),
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: softBorderColor),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: strongTextColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: mutedTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: mutedTextColor,
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Divider(height: 1, color: softBorderColor),
          ),
      ],
    );
  }
}
