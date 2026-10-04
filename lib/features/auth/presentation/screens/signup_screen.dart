import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/network_error_service.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../core/services/supabase_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;
  bool termsAccepted = false;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> handleSignUp() async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (name.isEmpty || phone.isEmpty || email.isEmpty || password.isEmpty) {
      showError('Missing Info', 'Please fill in all fields.');
      return;
    }

    if (!termsAccepted) {
      showError(
        'Terms Required',
        'Please review and accept the Terms and Conditions to create an account.',
      );
      return;
    }

    setState(() => loading = true);

    try {
      final response = await SupabaseService.client.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );

      final user = response.user;
      if (user != null) {
        try {
          await SupabaseService.client.from('users').upsert({
            'id': user.id,
            'name': name,
            'phone': phone,
            'email': email,
            'role': 'customer',
          });
        } catch (_) {
          // Keep sign-up usable even if the app-side user table shape differs.
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
        showError('Sign Up Failed', error.message);
      } else {
        showError('Sign Up Failed', NetworkErrorService.toUserMessage(error));
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

  void showTermsAndConditions() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terms and Conditions'),
        content: const SingleChildScrollView(
          child: Text(
            'To provide HMU services, we save the information you submit, including your name, phone number, email address, delivery details, order history, payment transaction details, support requests, and relevant device or notification data. We use this information to create and secure your account, process orders, provide deliveries, send service updates, and improve support.\n\n'
            'Food is prepared and supplied by individual restaurants. Each restaurant is responsible for the quality, safety, ingredients, allergens, and any food poisoning or allergic reaction connected to its food. HMU is a delivery platform and is not the food manufacturer or restaurant. To the extent permitted by applicable law, claims, charges, or liability for those matters must be directed to the responsible restaurant and not against the HMU platform.\n\n'
            'By creating an account, you confirm that you have read and accepted these Terms and Conditions.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
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
                'Create Account',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('Sign up to start ordering'),
              const SizedBox(height: 40),
              const Align(alignment: Alignment.centerLeft, child: Text('Name')),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(hintText: 'John Doe'),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Phone'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: '+266 5000 0000'),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Email'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Password'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'Create password'),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: termsAccepted,
                    onChanged: loading
                        ? null
                        : (value) {
                            setState(() => termsAccepted = value ?? false);
                          },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        children: [
                          const Text('I agree to the '),
                          InkWell(
                            onTap: showTermsAndConditions,
                            child: const Text(
                              'Terms and Conditions',
                              style: TextStyle(
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : handleSignUp,
                  child: Text(loading ? 'Signing up...' : 'Sign Up'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.push('/login'),
                child: const Text('Already have an account? Log In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
