import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/env.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_links.dart';
import 'auth_repository.dart';
import 'turnstile_box.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _repo = AuthRepository();
  final _captchaCtl = CaptchaController();
  String? _captcha;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _adult = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        _captchaCtl.reset(); // tokens are single use
        setState(() => _busy = false);
      }
    }
  }

  void _submit() {
    if (_signUp && !_adult) {
      setState(() => _error = 'Please confirm that you are 18 or older.');
      return;
    }
    final token = _captcha;
    if (Env.captchaEnabled && token == null) {
      setState(() => _error = 'Please complete the security check.');
      return;
    }
    _run(() => _signUp
        ? _repo.signUpWithEmail(_email.text.trim(), _password.text,
            adultConfirmed: _adult, captchaToken: token)
        : _repo.signInWithEmail(_email.text.trim(), _password.text, captchaToken: token));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Golden\nTongue', style: t.headlineLarge?.copyWith(color: AppColors.gold, fontSize: 44)),
                const SizedBox(height: AppSpacing.s),
                Text('Speak with presence. Connect with confidence.', style: t.bodySmall),
                const SizedBox(height: AppSpacing.xxl),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: AppSpacing.m),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (_signUp)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _adult,
                    onChanged: (v) => setState(() => _adult = v ?? false),
                    title: const Text('I am 18 or older'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.m),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                const SizedBox(height: AppSpacing.l),
                TurnstileBox(controller: _captchaCtl, onToken: (t) {
                  if (mounted) setState(() => _captcha = t);
                }),
                const SizedBox(height: AppSpacing.m),
                GoldButton(
                  label: _signUp ? 'Create account' : 'Sign in',
                  onPressed: _busy ? null : _submit,
                ),
                TextButton(
                  onPressed: () => setState(() => _signUp = !_signUp),
                  child: Text(_signUp ? 'I already have an account' : 'Create an account'),
                ),
                const Divider(color: AppColors.line, height: 32),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(_repo.signInWithGoogle),
                  child: const Text('Continue with Google'),
                ),
                const SizedBox(height: AppSpacing.s),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(_repo.signInWithApple),
                  child: const Text('Continue with Apple'),
                ),
                const SizedBox(height: AppSpacing.m),
                const LegalLinks(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
