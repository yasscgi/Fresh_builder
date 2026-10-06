import 'package:flutter/material.dart';

import 'cloud_auth_repository.dart';

class CloudAccountButton extends StatefulWidget {
  const CloudAccountButton({
    super.key,
    required this.cloudReady,
  });

  final bool cloudReady;

  @override
  State<CloudAccountButton> createState() => _CloudAccountButtonState();
}

class _CloudAccountButtonState extends State<CloudAccountButton> {
  CloudAuthRepository? _auth;

  @override
  void initState() {
    super.initState();
    if (widget.cloudReady) {
      _auth = CloudAuthRepository();
    }
  }

  @override
  void didUpdateWidget(covariant CloudAccountButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_auth == null && widget.cloudReady) {
      _auth = CloudAuthRepository();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    if (!widget.cloudReady || auth == null) {
      return IconButton(
        tooltip: 'Cloud is not configured',
        onPressed: null,
        icon: const Icon(Icons.cloud_off_rounded, size: 19),
      );
    }

    return StreamBuilder(
      stream: auth.authStateChanges,
      builder: (context, _) {
        final user = auth.currentUser;
        return IconButton(
          tooltip: user == null
              ? 'Sign in to FreshSTL'
              : user.email ?? 'FreshSTL account',
          onPressed: _openAccount,
          icon: Icon(
            user == null
                ? Icons.account_circle_outlined
                : Icons.account_circle_rounded,
            size: 21,
          ),
        );
      },
    );
  }

  Future<void> _openAccount() async {
    final auth = _auth;
    if (auth == null) return;

    if (auth.currentUser != null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('FreshSTL account'),
          content: Text(auth.currentUser?.email ?? 'Signed in'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.tonal(
              onPressed: () async {
                await auth.signOut();
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
      return;
    }

    final email = TextEditingController();
    final password = TextEditingController();
    var createAccount = false;
    var loading = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (loading) return;
              setDialogState(() {
                loading = true;
                error = null;
              });

              try {
                if (createAccount) {
                  await auth.signUpWithPassword(
                    email: email.text,
                    password: password.text,
                  );
                } else {
                  await auth.signInWithPassword(
                    email: email.text,
                    password: password.text,
                  );
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              } catch (exception) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  error = exception.toString();
                  loading = false;
                });
              }
            }

            return AlertDialog(
              title: Text(
                createAccount
                    ? 'Create FreshSTL account'
                    : 'Sign in to FreshSTL',
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      autofillHints: createAccount
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      onSubmitted: (_) => submit(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () {
                          setDialogState(() {
                            createAccount = !createAccount;
                            error = null;
                          });
                        },
                  child: Text(
                    createAccount
                        ? 'I already have an account'
                        : 'Create account',
                  ),
                ),
                FilledButton(
                  onPressed: loading ? null : submit,
                  child: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Text(createAccount ? 'Create' : 'Sign in'),
                ),
              ],
            );
          },
        );
      },
    );

    email.dispose();
    password.dispose();
  }
}
