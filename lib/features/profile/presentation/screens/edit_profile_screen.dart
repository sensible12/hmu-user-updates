import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/network_error_service.dart';
import '../../../../core/services/supabase_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    try {
      final row = await SupabaseService.client
          .from('users')
          .select('name, email')
          .eq('id', user.id)
          .maybeSingle();

      _nameController.text =
          row?['name']?.toString() ?? user.userMetadata?['name']?.toString() ?? '';
      _emailController.text = row?['email']?.toString() ?? user.email ?? '';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    final user = SupabaseService.currentUser;
    if (user == null || _saving) {
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      _showMessage('Name is required.');
      return;
    }

    setState(() => _saving = true);

    try {
      await SupabaseService.client.from('users').upsert({
        'id': user.id,
        'name': name,
        'email': email.isEmpty ? user.email : email,
      });

      if (!mounted) {
        return;
      }

      _showMessage('Profile updated.');
      context.pop();
    } catch (error) {
      final message = NetworkErrorService.isConnectivityIssue(error)
          ? NetworkErrorService.defaultNoInternetMessage
          : 'Unable to update profile: ${NetworkErrorService.toUserMessage(error)}';
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Your full name',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: Text(_saving ? 'Saving...' : 'Save Changes'),
                ),
              ],
            ),
    );
  }
}
