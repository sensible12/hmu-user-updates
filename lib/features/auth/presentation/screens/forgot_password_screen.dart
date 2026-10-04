import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/services/network_error_service.dart';
import '../../../../core/services/supabase_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailController = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> handleReset() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      showMessage('Missing Info', 'Please enter your email address.');
      return;
    }

    setState(() => loading = true);

    try {
      await SupabaseService.client.auth.resetPasswordForEmail(
        email,
        redirectTo: '${SupabaseConfig.url}/auth/v1/verify',
      );
      showMessage(
        'Check Your Email',
        'We sent you a password reset link. Follow the instructions to continue.',
      );
      if (mounted) {
        context.pop();
      }
    } catch (error) {
      if (NetworkErrorService.isConnectivityIssue(error)) {
        showMessage(
          'No Internet Connection',
          NetworkErrorService.defaultNoInternetMessage,
        );
      } else if (error is AuthException) {
        showMessage('Error', error.message);
      } else {
        showMessage('Error', NetworkErrorService.toUserMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void showMessage(String title, String message) {
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
              const Text(
                'Forgot Password',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('Enter your email and we will send you a reset link.'),
              const SizedBox(height: 40),
              const Align(alignment: Alignment.centerLeft, child: Text('Email')),
              const SizedBox(height: 8),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : handleReset,
                  child: Text(loading ? 'Sending...' : 'Send Reset Link'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
