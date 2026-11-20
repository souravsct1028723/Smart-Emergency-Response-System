import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'home_screen.dart';
import 'login_screen.dart';
import 'permission_onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/security_service.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  

Future<void> _handleGettingStarted(
  BuildContext context,
) async {
  // Check whether the user is already signed in.
  final currentUser = FirebaseAuth.instance.currentUser;

  if (currentUser == null) {
    // Only show Login/Register when no user is signed in.
    final authenticated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
    );

    if (authenticated != true || !context.mounted) {
      return;
    }
  }

  // Preserve the existing emergency security-password setup.
  final hasPassword = await SecurityService.hasPassword();

  if (!context.mounted) return;

  if (!hasPassword) {
    final passwordCreated =
        await _showCreatePasswordDialog(context);

    if (!passwordCreated || !context.mounted) {
      return;
    }
  }

  if (!context.mounted) return;

  final prefs = await SharedPreferences.getInstance();
  final user = FirebaseAuth.instance.currentUser;

  final onboardingKey = 'permissions_onboarding_completed_${user?.uid ?? "guest"}';

  final onboardingCompleted = prefs.getBool(onboardingKey) ?? false;

  if (!context.mounted) return;

  if (!onboardingCompleted) {
    final completed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const PermissionOnboardingScreen(),
      ),
    );

    if (completed != true || !context.mounted) {
      return;
    }

    await prefs.setBool(onboardingKey, true);
  }

  if (!context.mounted) return;

  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (context) => const HomeScreen(),
    ),
  );
}

  Future<bool> _showCreatePasswordDialog(
    BuildContext context,
  ) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    bool obscurePassword = true;
    bool obscureConfirm = true;
    String? errorMessage;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Create Security Password',
              ),

              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    const Text(
                      'Create a password that will be required '
                      'to cancel an emergency alert.',
                    ),

                    const SizedBox(height: 20),

                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscurePassword =
                                  !obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: confirmController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        hintText: 'Re-enter your password',
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureConfirm =
                                  !obscureConfirm;
                            });
                          },
                        ),
                      ),
                    ),

                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),

                      Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              actions: [

                ElevatedButton(
                  onPressed: () async {
                    final password =
                        passwordController.text.trim();

                    final confirmPassword =
                        confirmController.text.trim();

                    if (password.isEmpty) {
                      setDialogState(() {
                        errorMessage =
                            'Please enter a password.';
                      });

                      return;
                    }

                    if (password.length < 4) {
                      setDialogState(() {
                        errorMessage =
                            'Password must contain at least 4 characters.';
                      });

                      return;
                    }

                    if (password != confirmPassword) {
                      setDialogState(() {
                        errorMessage =
                            'Passwords do not match.';
                      });

                      return;
                    }

                    await SecurityService.setPassword(
                      password,
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(
                        dialogContext,
                        true,
                      );
                    }
                  },
                  child: const Text(
                    'Create Password',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      passwordController.dispose();
      confirmController.dispose();
    });

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 30,
          ),
          child: Column(
            children: [
              const Spacer(),

              const Text(
                'Guardian Alert',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              const Text(
                'Your personal emergency response companion',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    _handleGettingStarted(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'Getting Started',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}