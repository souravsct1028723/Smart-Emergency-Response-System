import 'package:flutter/material.dart';

import '../services/security_service.dart';
import '../services/biometric_service.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends State<SecuritySettingsScreen> {
  bool _isWorking = false;

  Future<bool> _verifyWithPassword() async {
    final passwordController = TextEditingController();

    bool obscurePassword = true;
    String? errorMessage;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Enter Current Password',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter your current Guardian Alert '
                    'security password.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Current Password',
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
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      false,
                    );
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final password =
                        passwordController.text;

                    if (password.isEmpty) {
                      setDialogState(() {
                        errorMessage =
                            'Please enter your password.';
                      });
                      return;
                    }

                    final correct =
                        await SecurityService.verifyPassword(
                      password,
                    );

                    if (correct) {
                      if (dialogContext.mounted) {
                        Navigator.pop(
                          dialogContext,
                          true,
                        );
                      }
                    } else {
                      setDialogState(() {
                        errorMessage =
                            'Incorrect password.';
                      });

                      passwordController.clear();
                    }
                  },
                  child: const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      passwordController.dispose();
    });

    return result ?? false;
  }

  Future<bool> _verifyWithBiometrics() async {
    setState(() {
      _isWorking = true;
    });

    final result =
        await BiometricService.authenticate();

    if (!mounted) {
      return false;
    }

    setState(() {
      _isWorking = false;
    });

    if (!result) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Biometric verification failed or was cancelled.',
          ),
        ),
      );
    }

    return result;
  }

  Future<void> _createNewPassword() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    bool obscurePassword = true;
    bool obscureConfirm = true;

    String? errorMessage;

    final newPassword = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Create New Password',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Enter your new Guardian Alert '
                      'security password.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'New Password',
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
                        labelText: 'Confirm New Password',
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
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final password =
                        passwordController.text.trim();

                    final confirmation =
                        confirmController.text.trim();

                    if (password.length < 4) {
                      setDialogState(() {
                        errorMessage =
                            'Password must contain at least 4 characters.';
                      });
                      return;
                    }

                    if (password != confirmation) {
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
                        password,
                      );
                    }
                  },
                  child: const Text(
                    'Update Password',
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

    if (newPassword != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Security password updated successfully.',
          ),
        ),
      );
    }
  }

  Future<void> _changePassword() async {
    if (_isWorking) {
      return;
    }

    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Verify Your Identity',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Choose how you want to verify your identity '
                  'before changing the security password.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        'biometric',
                      );
                    },
                    icon: const Icon(
                      Icons.fingerprint,
                    ),
                    label: const Text(
                      'Use Biometrics',
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        'password',
                      );
                    },
                    icon: const Icon(
                      Icons.lock_outline,
                    ),
                    label: const Text(
                      'Use Current Password',
                    ),
                  ),
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || method == null) {
      return;
    }

    bool verified = false;

    if (method == 'biometric') {
      verified = await _verifyWithBiometrics();
    } else if (method == 'password') {
      verified = await _verifyWithPassword();
    }

    if (!verified || !mounted) {
      return;
    }

    await _createNewPassword();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Security Settings',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.security,
              size: 60,
              color: Colors.red,
            ),

            const SizedBox(height: 20),

            const Text(
              'Security Settings',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'Manage the password used to cancel '
              'emergency alerts.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
              ),
            ),

            const SizedBox(height: 30),

            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.lock_reset,
                  color: Colors.red,
                ),
                title: const Text(
                  'Change Security Password',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Verify with biometrics or your current password.',
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                ),
                onTap: _changePassword,
              ),
            ),
          ],
        ),
      ),
    );
  }
}