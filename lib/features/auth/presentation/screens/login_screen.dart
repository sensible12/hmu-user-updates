import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/network_error_service.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../core/services/supabase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> handleLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showError('Missing Info', 'Please enter your email and password.');
      return;
    }

    setState(() => loading = true);

    try {
      final response = await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user != null) {
        try {
          await SupabaseService.client.from('users').upsert({
            'id': user.id,
            'name': user.userMetadata?['name']?.toString() ?? '',
            'phone': user.userMetadata?['phone']?.toString() ?? '',
            'email': email,
            'role': 'customer',
          });
        } catch (_) {
          // Keep login usable even if the app-side user table shape differs.
        }

        await PushNotificationService.ensureCurrentPushToken(user.id);

        if (mounted) {
          context.go('/');
        }
      }
    } catch (error) {
      if (NetworkErrorService.isConnectivityIssue(error)) {
        showError(
          'No Internet Connection',
          NetworkErrorService.defaultNoInternetMessage,
        );
      } else if (error is AuthException) {
        showError('Login Failed', error.message);
      } else {
        showError('Login Failed', NetworkErrorService.toUserMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void showError(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(title: Text(title), content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'new-hmu-logo.png',
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome Back',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('Log in to continue ordering'),
              const SizedBox(height: 40),
              const Align(alignment: Alignment.centerLeft, child: Text('Email')),
              const SizedBox(height: 8),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
              const SizedBox(height: 20),
              const Align(alignment: Alignment.centerLeft, child: Text('Password')),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'Enter password'),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push('/forgot-password'),
                  child: const Text('Forgot Password?'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : handleLogin,
                  child: Text(loading ? 'Logging in...' : 'Log In'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.push('/signup'),
                child: const Text("Don't have an account? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
