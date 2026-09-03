import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../config/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/gradient_button.dart';
import '../home/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    // The keyboard submit action bypasses the button's own loading guard.
    if (context.read<AuthProvider>().status == AuthStatus.loading) return;
    if (_formKey.currentState!.validate()) {
      final l10n = AppLocalizations.of(context);
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.register(
        email: _emailController.text.trim().toLowerCase(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        passwordConfirm: _confirmPasswordController.text,
      );

      if (success && mounted) {
        // Account created: let the password manager offer to save the
        // email/password pair it just saw.
        TextInput.finishAutofillContext();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? l10n.registrationFailed),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        constraints: const BoxConstraints.expand(),
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: AppTheme.pagePadding,
            child: ResponsiveCenter(
              maxWidth: 460,
              padding: EdgeInsets.zero,
              child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      l10n.registerTitle.toUpperCase(),
                      style: AppTheme.display(34),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.registerSubtitle,
                      style: const TextStyle(color: AppTheme.ink2, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    // Email field
                    CustomTextField(
                      controller: _emailController,
                      textInputAction: TextInputAction.next,
                      hintText: l10n.emailLabel,
                      labelText: l10n.emailLabel,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      prefixIcon: const Icon(
                        Icons.email,
                        color: AppTheme.textSecondary,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n.fieldRequired;
                        }
                        if (!value.contains('@')) {
                          return l10n.invalidEmail;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Username field
                    CustomTextField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      hintText: l10n.usernameLabel,
                      labelText: l10n.usernameLabel,
                      // No autofillHints on purpose: this is the public display
                      // name, not the login identifier (the email above is).
                      prefixIcon: const Icon(
                        Icons.person,
                        color: AppTheme.textSecondary,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n.fieldRequired;
                        }
                        if (value.length < 3) {
                          return l10n.usernameMinLength;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Password field
                    CustomTextField(
                      controller: _passwordController,
                      textInputAction: TextInputAction.next,
                      hintText: l10n.passwordLabel,
                      labelText: l10n.passwordLabel,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      prefixIcon: const Icon(
                        Icons.lock,
                        color: AppTheme.textSecondary,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n.fieldRequired;
                        }
                        if (value.length < 8) {
                          return l10n.passwordMinLength;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Confirm Password field
                    CustomTextField(
                      controller: _confirmPasswordController,
                      hintText: l10n.confirmPasswordLabel,
                      labelText: l10n.confirmPasswordLabel,
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _handleRegister(),
                      prefixIcon: const Icon(
                        Icons.lock,
                        color: AppTheme.textSecondary,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n.fieldRequired;
                        }
                        if (value != _passwordController.text) {
                          return l10n.passwordsDoNotMatch;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    // Register button
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, _) {
                        return GradientButton(
                          text: l10n.registerButton,
                          isLoading: authProvider.status == AuthStatus.loading,
                          onPressed: _handleRegister,
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${l10n.alreadyHaveAccount} ',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            l10n.loginLink,
                            style: const TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}
