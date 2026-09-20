import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'auth_service.dart';
import 'firebase_options.dart';
import 'legal_pages.dart';
import 'medication.dart';
import 'medication_storage.dart';
import 'onboarding_service.dart';
import 'time_helper.dart';

enum _AuthenticationMode { signIn, createAccount }

enum _PendingEligibilityAction { createAccount, guest }

class AuthenticationPage extends StatefulWidget {
  final bool showBackButton;
  final bool allowGuest;

  const AuthenticationPage({
    super.key,
    this.showBackButton = false,
    this.allowGuest = true,
  });

  @override
  State<AuthenticationPage> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends State<AuthenticationPage> {
  static const String adultEligibilityPreferenceKey =
      "adult_eligibility_confirmed_v1";

  final TextEditingController emailController = TextEditingController();
  final TextEditingController preferredNameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  _AuthenticationMode mode = _AuthenticationMode.signIn;
  bool hidePassword = true;
  bool isWorking = false;
  bool eligibilityLoaded = false;
  bool adultEligibilityConfirmed = false;
  bool showAdultEligibility = false;
  bool legalConsentAccepted = false;
  _PendingEligibilityAction? pendingEligibilityAction;
  DateTime? selectedBirthDate;
  String errorText = "";

  bool get isVietnamese {
    return AppLanguage.currentLanguage.value == "vi";
  }

  String tr(String english, String vietnamese) {
    return isVietnamese ? vietnamese : english;
  }

  @override
  void initState() {
    super.initState();
    unawaited(loadAdultEligibility());
  }

  Future<void> loadAdultEligibility() async {
    var isConfirmed = false;

    try {
      final preferences = await SharedPreferences.getInstance();
      isConfirmed = preferences.getBool(adultEligibilityPreferenceKey) ?? false;
    } catch (_) {
      // The eligibility screen remains available even if preferences fail.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      adultEligibilityConfirmed = isConfirmed;
      eligibilityLoaded = true;
    });
  }

  int ageForBirthDate(DateTime birthDate, DateTime today) {
    var age = today.year - birthDate.year;
    final birthdayHasPassed =
        today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);

    if (!birthdayHasPassed) {
      age--;
    }

    return age;
  }

  int? get selectedAge {
    final birthDate = selectedBirthDate;

    if (birthDate == null) {
      return null;
    }

    return ageForBirthDate(birthDate, DateTime.now());
  }

  bool get selectedBirthDateIsAdult {
    final age = selectedAge;
    return age != null && age >= 18;
  }

  String formattedBirthDate(DateTime date) {
    if (isVietnamese) {
      final day = date.day.toString().padLeft(2, "0");
      final month = date.month.toString().padLeft(2, "0");
      return "$day/$month/${date.year}";
    }

    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];

    return "${months[date.month - 1]} ${date.day}, ${date.year}";
  }

  Future<void> chooseBirthDate() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate:
          selectedBirthDate ??
          DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(today.year - 120),
      lastDate: today,
      helpText: tr("Select date of birth", "Chọn ngày sinh"),
      cancelText: tr("Cancel", "Hủy"),
      confirmText: tr("Use this date", "Dùng ngày này"),
      builder: (context, child) {
        final theme = Theme.of(context);

        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: AppTheme.primaryColor,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (date == null || !mounted) {
      return;
    }

    setState(() {
      selectedBirthDate = DateTime(date.year, date.month, date.day);
    });
  }

  Future<void> confirmAdultEligibility() async {
    if (!selectedBirthDateIsAdult || isWorking) {
      return;
    }

    setState(() {
      isWorking = true;
    });

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(adultEligibilityPreferenceKey, true);
    } catch (_) {
      // A local preference failure should not trap an eligible adult here.
    }

    if (!mounted) {
      return;
    }

    final nextAction = pendingEligibilityAction;
    setState(() {
      adultEligibilityConfirmed = true;
      showAdultEligibility = false;
      pendingEligibilityAction = null;
      isWorking = false;
    });

    if (nextAction == _PendingEligibilityAction.createAccount) {
      await submit();
    } else if (nextAction == _PendingEligibilityAction.guest) {
      await continueAsGuest();
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    preferredNameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void changeMode(_AuthenticationMode nextMode) {
    if (isWorking) {
      return;
    }

    setState(() {
      mode = nextMode;
      errorText = "";
      confirmPasswordController.clear();
    });
  }

  Future<void> openTermsOfUse() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const TermsOfUsePage()),
    );
  }

  Future<void> openPrivacyPolicy() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const PrivacyPolicyPage()),
    );
  }

  Future<void> submit() async {
    if (isWorking) {
      return;
    }

    FocusScope.of(context).unfocus();

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (mode == _AuthenticationMode.createAccount &&
        preferredNameController.text.trim().isEmpty) {
      setState(() {
        errorText = tr(
          "Please enter the name you would like us to use.",
          "Vui lòng nhập tên bạn muốn chúng tôi sử dụng.",
        );
      });
      return;
    }

    if (mode == _AuthenticationMode.createAccount && !legalConsentAccepted) {
      setState(() {
        errorText = tr(
          "Please agree to the Terms of Use and Privacy Policy before creating an account.",
          "Vui lòng đồng ý với Điều Khoản Sử Dụng và Chính Sách Riêng Tư trước khi tạo tài khoản.",
        );
      });
      return;
    }

    if (mode == _AuthenticationMode.createAccount &&
        password != confirmPasswordController.text) {
      setState(() {
        errorText = tr(
          "The passwords do not match.",
          "Hai mật khẩu không giống nhau.",
        );
      });
      return;
    }

    if (mode == _AuthenticationMode.createAccount &&
        !adultEligibilityConfirmed) {
      setState(() {
        pendingEligibilityAction = _PendingEligibilityAction.createAccount;
        showAdultEligibility = true;
        selectedBirthDate = null;
      });
      return;
    }

    setState(() {
      isWorking = true;
      errorText = "";
    });

    try {
      final guestMedications = AuthService.isGuest
          ? await MedicationStorage.loadCurrentLocalMedications()
          : <Medication>[];

      if (mode == _AuthenticationMode.createAccount) {
        final credential = await AuthService.createAccount(
          email: email,
          password: password,
        );
        await AuthService.updatePreferredName(preferredNameController.text);
        final createdUserId = credential.user?.uid ?? AuthService.userId;
        await LegalConsentService.recordAcceptance(userId: createdUserId);
        await OnboardingService.requestForNewAccount(createdUserId);

        try {
          await AuthService.sendEmailVerification(
            languageCode: isVietnamese ? "vi" : "en",
          );
        } catch (_) {
          // The account remains usable; verification can be resent later.
        }

        if (guestMedications.isNotEmpty) {
          await MedicationStorage.mergeMedicationsIntoCurrentUser(
            guestMedications,
          );
          await MedicationStorage.clearGuestLocalMedications();
        } else {
          await MedicationStorage.syncNow();
        }
      } else {
        await AuthService.login(email: email, password: password);

        if (guestMedications.isNotEmpty) {
          await MedicationStorage.mergeMedicationsIntoCurrentUser(
            guestMedications,
          );
          await MedicationStorage.clearGuestLocalMedications();
        } else {
          await MedicationStorage.syncNow();
        }
      }

      if (!mounted) {
        return;
      }

      if (widget.showBackButton && Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorText = AuthService.errorMessage(error, vietnamese: isVietnamese);
      });
    } finally {
      if (mounted) {
        setState(() {
          isWorking = false;
        });
      }
    }
  }

  Future<void> continueAsGuest() async {
    if (isWorking || !widget.allowGuest) {
      return;
    }

    if (!legalConsentAccepted) {
      setState(() {
        errorText = tr(
          "Please agree to the Terms of Use and Privacy Policy before continuing as a guest.",
          "Vui lòng đồng ý với Điều Khoản Sử Dụng và Chính Sách Riêng Tư trước khi tiếp tục với tư cách khách.",
        );
      });
      return;
    }

    if (!adultEligibilityConfirmed) {
      setState(() {
        pendingEligibilityAction = _PendingEligibilityAction.guest;
        showAdultEligibility = true;
        selectedBirthDate = null;
      });
      return;
    }

    setState(() {
      isWorking = true;
      errorText = "";
    });

    try {
      final credential = await AuthService.continueAsGuest();
      final guestUserId = credential.user?.uid ?? AuthService.userId;
      await LegalConsentService.recordAcceptance(userId: guestUserId);
      await OnboardingService.requestForGuest(guestUserId);
      await MedicationStorage.loadMedications();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorText = AuthService.errorMessage(error, vietnamese: isVietnamese);
      });
    } finally {
      if (mounted) {
        setState(() {
          isWorking = false;
        });
      }
    }
  }

  Future<void> sendPasswordReset() async {
    final resetController = TextEditingController(
      text: emailController.text.trim(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr("Reset password", "Đặt lại mật khẩu")),
          content: TextField(
            controller: resetController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: "Email",
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: Text(tr("Cancel", "Hủy")),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, resetController.text.trim());
              },
              child: Text(tr("Send email", "Gửi email")),
            ),
          ],
        );
      },
    );

    resetController.dispose();

    if (email == null || email.trim().isEmpty || !mounted) {
      return;
    }

    setState(() {
      isWorking = true;
      errorText = "";
    });

    try {
      await AuthService.sendPasswordResetEmail(email: email);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr("Password reset email sent.", "Đã gửi email đặt lại mật khẩu."),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorText = AuthService.errorMessage(error, vietnamese: isVietnamese);
      });
    } finally {
      if (mounted) {
        setState(() {
          isWorking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!eligibilityLoaded) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: AppTheme.pageDecoration(),
          alignment: Alignment.center,
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (showAdultEligibility) {
      return buildAdultEligibilityGate();
    }

    final creatingAccount = mode == _AuthenticationMode.createAccount;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: isWorking
                              ? null
                              : () {
                                  setState(() {
                                    showAdultEligibility = false;
                                    pendingEligibilityAction = null;
                                    selectedBirthDate = null;
                                  });
                                },
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: isWorking
                              ? null
                              : () async {
                                  final nextLanguage = isVietnamese
                                      ? "en"
                                      : "vi";
                                  await AppLanguage.changeLanguage(
                                    nextLanguage,
                                  );

                                  if (mounted) {
                                    setState(() {});
                                  }
                                },
                          icon: const Icon(Icons.language_rounded),
                          label: Text(isVietnamese ? "English" : "Tiếng Việt"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.28,
                            ),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.medication_liquid_rounded,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      tr("Medication Reminder", "Nhắc Nhở Uống Thuốc"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      creatingAccount
                          ? tr(
                              "Create an account to securely sync your medications.",
                              "Tạo tài khoản để đồng bộ thuốc của bạn an toàn.",
                            )
                          : tr(
                              "Sign in to access your medication schedule on this device.",
                              "Đăng nhập để truy cập lịch uống thuốc trên thiết bị này.",
                            ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: AutofillGroup(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _ModeButton(
                                    label: tr("Sign in", "Đăng nhập"),
                                    selected: !creatingAccount,
                                    onTap: () {
                                      changeMode(_AuthenticationMode.signIn);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ModeButton(
                                    label: tr(
                                      "Create account",
                                      "Tạo tài khoản",
                                    ),
                                    selected: creatingAccount,
                                    onTap: () {
                                      changeMode(
                                        _AuthenticationMode.createAccount,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (creatingAccount) ...[
                              TextField(
                                controller: preferredNameController,
                                enabled: !isWorking,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                decoration: _inputDecoration(
                                  label: tr(
                                    "What should we call you?",
                                    "Bạn muốn chúng tôi gọi bạn là gì?",
                                  ),
                                  icon: Icons.badge_outlined,
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextField(
                              controller: emailController,
                              enabled: !isWorking,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: _inputDecoration(
                                label: "Email",
                                icon: Icons.email_outlined,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: passwordController,
                              enabled: !isWorking,
                              obscureText: hidePassword,
                              textInputAction: creatingAccount
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              autofillHints: creatingAccount
                                  ? const [AutofillHints.newPassword]
                                  : const [AutofillHints.password],
                              onSubmitted: creatingAccount
                                  ? null
                                  : (_) {
                                      submit();
                                    },
                              decoration: _inputDecoration(
                                label: tr("Password", "Mật khẩu"),
                                icon: Icons.lock_outline_rounded,
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      hidePassword = !hidePassword;
                                    });
                                  },
                                  icon: Icon(
                                    hidePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            if (creatingAccount) ...[
                              const SizedBox(height: 14),
                              TextField(
                                controller: confirmPasswordController,
                                enabled: !isWorking,
                                obscureText: hidePassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                onSubmitted: (_) {
                                  submit();
                                },
                                decoration: _inputDecoration(
                                  label: tr(
                                    "Confirm password",
                                    "Xác nhận mật khẩu",
                                  ),
                                  icon: Icons.lock_reset_rounded,
                                ),
                              ),
                            ],
                            if (!creatingAccount) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: isWorking
                                      ? null
                                      : sendPasswordReset,
                                  child: Text(
                                    tr("Forgot password?", "Quên mật khẩu?"),
                                  ),
                                ),
                              ),
                            ] else
                              const SizedBox(height: 18),
                            if (creatingAccount || widget.allowGuest) ...[
                              Material(
                                color: const Color(0xFFFFF7FB),
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17),
                                  side: BorderSide(
                                    color: AppTheme.primaryColor.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    CheckboxListTile(
                                      key: const Key("legal-consent-checkbox"),
                                      value: legalConsentAccepted,
                                      onChanged: isWorking
                                          ? null
                                          : (value) {
                                              setState(() {
                                                legalConsentAccepted =
                                                    value ?? false;
                                                errorText = "";
                                              });
                                            },
                                      activeColor: AppTheme.primaryColor,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      contentPadding: const EdgeInsets.fromLTRB(
                                        8,
                                        4,
                                        10,
                                        0,
                                      ),
                                      title: Text(
                                        tr(
                                          "I have read and agree to the policies below.",
                                          "Tôi đã đọc và đồng ý với các chính sách dưới đây.",
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFF334155),
                                          fontSize: 13,
                                          height: 1.35,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        46,
                                        0,
                                        10,
                                        8,
                                      ),
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 4,
                                        runSpacing: 0,
                                        children: [
                                          TextButton(
                                            key: const Key("open-terms-of-use"),
                                            onPressed: isWorking
                                                ? null
                                                : openTermsOfUse,
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            child: Text(
                                              tr(
                                                "Terms of Use",
                                                "Điều Khoản Sử Dụng",
                                              ),
                                            ),
                                          ),
                                          const Text(
                                            "•",
                                            style: TextStyle(
                                              color: Color(0xFF94A3B8),
                                            ),
                                          ),
                                          TextButton(
                                            key: const Key(
                                              "open-privacy-policy",
                                            ),
                                            onPressed: isWorking
                                                ? null
                                                : openPrivacyPolicy,
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            child: Text(
                                              tr(
                                                "Privacy Policy",
                                                "Chính Sách Riêng Tư",
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (errorText.isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1F2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFFDA4AF),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: Color(0xFFE11D48),
                                      size: 21,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        errorText,
                                        style: const TextStyle(
                                          color: Color(0xFF9F1239),
                                          fontWeight: FontWeight.w700,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton.icon(
                                onPressed:
                                    isWorking ||
                                        (creatingAccount &&
                                            !legalConsentAccepted)
                                    ? null
                                    : submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                icon: isWorking
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        creatingAccount
                                            ? Icons.person_add_alt_1_rounded
                                            : Icons.login_rounded,
                                      ),
                                label: Text(
                                  creatingAccount
                                      ? tr("Create account", "Tạo tài khoản")
                                      : tr("Sign in", "Đăng nhập"),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.allowGuest) ...[
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: isWorking || !legalConsentAccepted
                            ? null
                            : continueAsGuest,
                        icon: const Icon(Icons.person_outline_rounded),
                        label: Text(
                          tr("Continue as guest", "Tiếp tục với tư cách khách"),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          "Guest data can be upgraded to an email account later.",
                          "Dữ liệu khách có thể nâng cấp thành tài khoản email sau.",
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildAdultEligibilityGate() {
    final birthDate = selectedBirthDate;
    final age = selectedAge;
    final hasBirthDate = birthDate != null;
    final isAdult = selectedBirthDateIsAdult;
    final statusColor = isAdult
        ? const Color(0xFF16A34A)
        : const Color(0xFFE11D48);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (widget.showBackButton)
                          IconButton.filledTonal(
                            onPressed: isWorking
                                ? null
                                : () {
                                    Navigator.pop(context, false);
                                  },
                            icon: const Icon(Icons.arrow_back_rounded),
                          )
                        else
                          const SizedBox(width: 48),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: isWorking
                              ? null
                              : () async {
                                  await AppLanguage.changeLanguage(
                                    isVietnamese ? "en" : "vi",
                                  );

                                  if (mounted) {
                                    setState(() {});
                                  }
                                },
                          icon: const Icon(Icons.language_rounded),
                          label: Text(isVietnamese ? "English" : "Tiếng Việt"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryColor,
                            AppTheme.primaryColor.withValues(alpha: 0.72),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.25,
                            ),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.health_and_safety_rounded,
                        color: Colors.white,
                        size: 46,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      tr("Before you continue", "Trước khi tiếp tục"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      tr(
                        "Medication Reminder is designed for adults age 18 and older.",
                        "Ứng dụng Nhắc Nhở Uống Thuốc dành cho người từ 18 tuổi trở lên.",
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.97),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0F172A,
                            ).withValues(alpha: 0.07),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            tr(
                              "What is your date of birth?",
                              "Ngày sinh của bạn là ngày nào?",
                            ),
                            style: const TextStyle(
                              color: Color(0xFF172033),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            tr(
                              "Choose the exact month, day, and year.",
                              "Chọn chính xác ngày, tháng và năm.",
                            ),
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: isWorking ? null : chooseBirthDate,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                              alignment: Alignment.centerLeft,
                              side: BorderSide(
                                color: hasBirthDate
                                    ? AppTheme.primaryColor
                                    : const Color(0xFFD7DEE8),
                                width: hasBirthDate ? 1.8 : 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cake_outlined,
                                  color: AppTheme.primaryColor,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    hasBirthDate
                                        ? formattedBirthDate(birthDate)
                                        : tr(
                                            "Select date of birth",
                                            "Chọn ngày sinh",
                                          ),
                                    style: TextStyle(
                                      color: hasBirthDate
                                          ? const Color(0xFF172033)
                                          : const Color(0xFF64748B),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.calendar_month_rounded,
                                  color: Color(0xFF94A3B8),
                                ),
                              ],
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            child: !hasBirthDate
                                ? const SizedBox.shrink()
                                : Container(
                                    key: ValueKey<bool>(isAdult),
                                    margin: const EdgeInsets.only(top: 14),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(
                                        alpha: 0.09,
                                      ),
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(
                                        color: statusColor.withValues(
                                          alpha: 0.28,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          isAdult
                                              ? Icons.check_circle_rounded
                                              : Icons.info_rounded,
                                          color: statusColor,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Text(
                                            isAdult
                                                ? tr(
                                                    "Age verified. You can continue.",
                                                    "Đã xác minh tuổi. Bạn có thể tiếp tục.",
                                                  )
                                                : tr(
                                                    "You are $age. This app is available only to adults age 18 or older.",
                                                    "Bạn $age tuổi. Ứng dụng chỉ dành cho người từ 18 tuổi trở lên.",
                                                  ),
                                            style: TextStyle(
                                              color: statusColor,
                                              height: 1.3,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 19,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr(
                                    "Your birth date is used only for this age check. It is not saved or uploaded.",
                                    "Ngày sinh chỉ được dùng để kiểm tra tuổi. Ngày sinh không được lưu hoặc tải lên.",
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 54,
                            child: FilledButton.icon(
                              onPressed: isAdult && !isWorking
                                  ? confirmAdultEligibility
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17),
                                ),
                              ),
                              icon: isWorking
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_rounded),
                              label: Text(
                                tr("Continue", "Tiếp tục"),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFDCE3EC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFDCE3EC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.8),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.primaryColor : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF475467),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> with WidgetsBindingObserver {
  bool isWorking = false;
  bool verificationEmailSent = false;
  bool waitingForVerificationReturn = false;
  bool verificationRecoveryRunning = false;

  bool get isVietnamese {
    return AppLanguage.currentLanguage.value == "vi";
  }

  String tr(String english, String vietnamese) {
    return isVietnamese ? vietnamese : english;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(restorePendingVerification());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(recoverVerificationAfterReturn());
    }
  }

  Future<void> restorePendingVerification() async {
    final pending = await AuthService.hasPendingEmailVerification();

    if (!mounted || !pending) {
      return;
    }

    setState(() {
      verificationEmailSent = true;
      waitingForVerificationReturn = true;
    });

    await recoverVerificationAfterReturn();
  }

  Future<void> recoverVerificationAfterReturn() async {
    if (verificationRecoveryRunning || isWorking) {
      return;
    }

    verificationRecoveryRunning = true;

    try {
      final pending =
          waitingForVerificationReturn ||
          await AuthService.hasPendingEmailVerification();

      if (!pending || !mounted) {
        return;
      }

      waitingForVerificationReturn = false;
      await checkVerification(quietWhenPending: true, retryBriefly: true);
    } finally {
      verificationRecoveryRunning = false;
    }
  }

  void showMessage(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB42318) : null,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Future<void> editPreferredName() async {
    if (isWorking || AuthService.isGuest) {
      return;
    }

    final currentName = AuthService.currentUser?.displayName?.trim() ?? "";
    final controller = TextEditingController(text: currentName);
    String? validationMessage;

    final selectedName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final value = controller.text.trim().replaceAll(
                RegExp(r"\s+"),
                " ",
              );

              if (value.isEmpty) {
                setDialogState(() {
                  validationMessage = tr(
                    "Please enter the name you would like us to use.",
                    "Vui lòng nhập tên bạn muốn chúng tôi sử dụng.",
                  );
                });
                return;
              }

              Navigator.pop(dialogContext, value);
            }

            return AlertDialog(
              icon: Icon(Icons.badge_outlined, color: AppTheme.primaryColor),
              title: Text(
                tr("What should we call you?", "Bạn muốn được gọi là gì?"),
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 50,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(
                  labelText: tr("Preferred name", "Tên muốn được gọi"),
                  helperText: tr(
                    "Used in app greetings and account emails.",
                    "Dùng trong lời chào và email tài khoản.",
                  ),
                  errorText: validationMessage,
                ),
                onChanged: (_) {
                  if (validationMessage != null) {
                    setDialogState(() => validationMessage = null);
                  }
                },
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr("Cancel", "Hủy")),
                ),
                FilledButton(
                  onPressed: submit,
                  child: Text(tr("Save name", "Lưu tên")),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (selectedName == null || selectedName == currentName || !mounted) {
      return;
    }

    setState(() => isWorking = true);

    try {
      await AuthService.updatePreferredName(selectedName);
      await MedicationStorage.refreshNotificationSchedule();

      if (!mounted) {
        return;
      }

      setState(() {});
      showMessage(
        tr(
          "Your preferred name was updated.",
          "Tên muốn được gọi đã được cập nhật.",
        ),
      );
    } catch (error) {
      showMessage(
        AuthService.errorMessage(error, vietnamese: isVietnamese),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => isWorking = false);
      }
    }
  }

  Future<void> syncNow() async {
    if (isWorking) {
      return;
    }

    setState(() {
      isWorking = true;
    });

    try {
      await AuthService.refreshCloudSession(forceRefresh: true);
    } catch (_) {
      // MedicationStorage reports the detailed Firebase failure below.
    }

    final success = await MedicationStorage.syncNow();
    final medicationCount = success
        ? (await MedicationStorage.loadCurrentLocalMedications()).length
        : 0;

    if (!mounted) {
      return;
    }

    setState(() {
      isWorking = false;
    });

    showMessage(
      success
          ? tr(
              medicationCount == 1
                  ? "1 medication synced. You can now open the same account on your other device."
                  : "$medicationCount medications synced. You can now open the same account on your other device.",
              "Đã đồng bộ $medicationCount thuốc. Bây giờ bạn có thể mở cùng tài khoản trên thiết bị khác.",
            )
          : MedicationStorage.syncFailureMessage(vietnamese: isVietnamese),
      error: !success,
    );
  }

  Uri get emailInboxUri {
    final email = AuthService.userEmail.toLowerCase();

    if (email.endsWith("@outlook.com") ||
        email.endsWith("@hotmail.com") ||
        email.endsWith("@live.com")) {
      return Uri.parse("https://outlook.live.com/mail/0/inbox");
    }

    if (email.endsWith("@yahoo.com")) {
      return Uri.parse("https://mail.yahoo.com/");
    }

    if (email.endsWith("@icloud.com") || email.endsWith("@me.com")) {
      return Uri.parse("https://www.icloud.com/mail/");
    }

    return Uri.parse("https://mail.google.com/mail/u/0/#inbox");
  }

  Future<void> openEmailInbox() async {
    await AuthService.rememberPendingEmailVerification();
    waitingForVerificationReturn = true;

    try {
      final opened = await launchUrl(
        emailInboxUri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        waitingForVerificationReturn = false;
        showMessage(
          tr(
            "Could not open your email. Open your email app and find the newest Medication Reminder message.",
            "Không thể mở email. Hãy mở ứng dụng email và tìm thư Medication Reminder mới nhất.",
          ),
          error: true,
        );
      }
    } catch (_) {
      waitingForVerificationReturn = false;
      showMessage(
        tr(
          "Could not open your email. Open your email app and find the newest Medication Reminder message.",
          "Không thể mở email. Hãy mở ứng dụng email và tìm thư Medication Reminder mới nhất.",
        ),
        error: true,
      );
    }
  }

  Future<void> sendVerificationEmail() async {
    if (isWorking) return;
    setState(() => isWorking = true);

    try {
      await AuthService.sendEmailVerification(
        languageCode: isVietnamese ? "vi" : "en",
      );

      if (mounted) {
        setState(() => verificationEmailSent = true);
      }

      showMessage(
        tr(
          "Verification email sent. Use the newest email, then return to the app.",
          "Đã gửi email xác minh. Hãy dùng thư mới nhất, rồi quay lại ứng dụng.",
        ),
      );
    } catch (error) {
      showMessage(
        AuthService.errorMessage(error, vietnamese: isVietnamese),
        error: true,
      );
    } finally {
      if (mounted) setState(() => isWorking = false);
    }
  }

  Future<void> beginEmailVerification() async {
    if (verificationEmailSent) {
      await openEmailInbox();
      return;
    }

    await sendVerificationEmail();

    if (mounted && verificationEmailSent) {
      await openEmailInbox();
    }
  }

  Future<void> checkVerification({
    bool quietWhenPending = false,
    bool retryBriefly = false,
  }) async {
    if (isWorking) return;
    setState(() => isWorking = true);

    try {
      final attempts = retryBriefly ? 3 : 1;

      for (var attempt = 0; attempt < attempts; attempt += 1) {
        await AuthService.reloadCurrentUser();

        if (AuthService.isEmailVerified) {
          break;
        }

        if (attempt < attempts - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: 700 * (attempt + 1)),
          );
        }
      }

      if (!mounted) return;
      final verified = AuthService.isEmailVerified;

      if (verified) {
        await AuthService.clearPendingEmailVerification();
        final syncSucceeded = await MedicationStorage.syncNow();

        if (!syncSucceeded) {
          if (!mounted) return;
          showMessage(
            MedicationStorage.syncFailureMessage(vietnamese: isVietnamese),
            error: true,
          );
          return;
        }
      }

      if (!mounted) return;
      setState(() {});
      if (verified) {
        final count =
            (await MedicationStorage.loadCurrentLocalMedications()).length;
        showMessage(
          tr(
            "Email verified and $count medications synced.",
            "Email đã xác minh và đã đồng bộ $count thuốc.",
          ),
        );
      } else {
        await AuthService.rememberPendingEmailVerification();

        if (quietWhenPending) {
          return;
        }

        showMessage(
          tr(
            "Not verified yet. Open the newest email, tap Verify Email, then return here.",
            "Email chưa xác minh. Mở thư mới nhất, nhấn Xác Minh Email, rồi quay lại đây.",
          ),
          error: true,
        );
      }
    } catch (error) {
      showMessage(
        AuthService.errorMessage(error, vietnamese: isVietnamese),
        error: true,
      );
    } finally {
      if (mounted) setState(() => isWorking = false);
    }
  }

  Future<void> openUpgradeOrSignIn() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const AuthenticationPage(showBackButton: true, allowGuest: false),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> signOut() async {
    if (isWorking) {
      return;
    }

    setState(() {
      isWorking = true;
    });

    try {
      await MedicationStorage.prepareForSignOut();
      await AuthService.logout();

      if (!mounted) {
        return;
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isWorking = false;
      });

      showMessage(
        AuthService.errorMessage(error, vietnamese: isVietnamese),
        error: true,
      );
    }
  }

  Future<void> deleteAccount() async {
    if (isWorking) {
      return;
    }

    final deletingGuest = AuthService.isGuest;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFD92D20),
            size: 36,
          ),
          title: Text(
            tr("Delete account and data?", "Xóa tài khoản và dữ liệu?"),
          ),
          content: Text(
            deletingGuest
                ? tr(
                    "This permanently deletes the guest account and its locally stored medication data. This action cannot be undone.",
                    "Thao tác này sẽ xóa vĩnh viễn tài khoản khách và dữ liệu thuốc lưu cục bộ. Không thể hoàn tác.",
                  )
                : tr(
                    "This permanently deletes this account and its medication data from Firebase. This action cannot be undone.",
                    "Thao tác này sẽ xóa vĩnh viễn tài khoản và dữ liệu thuốc khỏi Firebase. Không thể hoàn tác.",
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(tr("Cancel", "Hủy")),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD92D20),
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(tr("Delete permanently", "Xóa vĩnh viễn")),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      isWorking = true;
    });

    try {
      await MedicationStorage.deleteCurrentAccountAndData();

      if (!mounted) {
        return;
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isWorking = false;
      });

      showMessage(
        AuthService.errorMessage(error, vietnamese: isVietnamese),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final guest = AuthService.isGuest;
    final email = AuthService.userEmail;
    final preferredName = AuthService.currentUser?.displayName?.trim() ?? "";
    final emailVerified = AuthService.isEmailVerified;
    final macFirebaseConfigurationNeedsUpdate =
        defaultTargetPlatform == TargetPlatform.macOS &&
        DefaultFirebaseOptions.macos.iosBundleId !=
            "com.duytruong.medicationreminder.macos";

    return Scaffold(
      appBar: AppBar(
        title: Text(tr("Account & Cloud Sync", "Tài Khoản & Đồng Bộ")),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: AppTheme.pagePadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Text(
                                guest
                                    ? tr("Guest account", "Tài khoản khách")
                                    : preferredName.isEmpty
                                    ? email
                                    : preferredName,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Color(0xFF1E2A3A),
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          if (!guest && preferredName.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              email,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 7),
                          Text(
                            guest
                                ? tr(
                                    "Your medication data is stored locally on this device. Upgrade to securely sync it across devices.",
                                    "Dữ liệu thuốc đang được lưu cục bộ trên thiết bị này. Hãy nâng cấp để đồng bộ an toàn trên nhiều thiết bị.",
                                  )
                                : tr(
                                    "Your medication list is saved on this device and privately synced when Firebase is available.",
                                    "Danh sách thuốc được lưu trên thiết bị và đồng bộ riêng tư khi Firebase sẵn sàng.",
                                  ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!guest) ...[
                      _AccountActionCard(
                        icon: Icons.badge_outlined,
                        title: tr("Preferred name", "Tên muốn được gọi"),
                        subtitle: preferredName.isEmpty
                            ? tr("Add your name", "Thêm tên của bạn")
                            : preferredName,
                        onTap: isWorking ? null : editPreferredName,
                      ),
                      const SizedBox(height: 12),
                      _AccountActionCard(
                        icon: emailVerified
                            ? Icons.mark_email_read_rounded
                            : Icons.mark_email_unread_rounded,
                        iconColor: emailVerified
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFF59E0B),
                        title: emailVerified
                            ? tr("Email verified", "Email đã xác minh")
                            : verificationEmailSent
                            ? tr(
                                "Verification email sent",
                                "Đã gửi email xác minh",
                              )
                            : tr("Verify your email", "Xác minh email"),
                        onTap: null,
                      ),
                      if (!emailVerified) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: isWorking
                                ? null
                                : beginEmailVerification,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: Icon(
                              verificationEmailSent
                                  ? Icons.open_in_new_rounded
                                  : Icons.send_rounded,
                            ),
                            label: Text(
                              verificationEmailSent
                                  ? tr(
                                      "Open verification email",
                                      "Mở email xác minh",
                                    )
                                  : tr("Verify email", "Xác minh email"),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _SyncStatusCard(
                        macFirebaseConfigurationNeedsUpdate:
                            macFirebaseConfigurationNeedsUpdate,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (guest) ...[
                      _AccountActionCard(
                        icon: Icons.person_add_alt_1_rounded,
                        title: tr(
                          "Upgrade or sign in",
                          "Nâng cấp hoặc đăng nhập",
                        ),
                        onTap: isWorking ? null : openUpgradeOrSignIn,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!guest) ...[
                      _AccountActionCard(
                        icon: Icons.cloud_sync_rounded,
                        title: defaultTargetPlatform == TargetPlatform.iOS
                            ? tr(
                                "Upload & sync iPhone medications",
                                "Tải lên & đồng bộ thuốc trên iPhone",
                              )
                            : defaultTargetPlatform == TargetPlatform.macOS
                            ? tr(
                                "Download & sync Mac medications",
                                "Tải xuống & đồng bộ thuốc trên Mac",
                              )
                            : tr("Sync medications", "Đồng bộ thuốc"),
                        trailing: isWorking
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : macFirebaseConfigurationNeedsUpdate
                            ? const Icon(
                                Icons.lock_outline_rounded,
                                color: Color(0xFFB54708),
                              )
                            : null,
                        onTap: isWorking || macFirebaseConfigurationNeedsUpdate
                            ? null
                            : syncNow,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _AccountActionCard(
                      icon: Icons.logout_rounded,
                      title: tr("Sign out", "Đăng xuất"),
                      onTap: isWorking ? null : signOut,
                    ),
                    const SizedBox(height: 12),
                    _AccountActionCard(
                      icon: Icons.delete_forever_rounded,
                      iconColor: const Color(0xFFD92D20),
                      title: tr(
                        "Delete account and data",
                        "Xóa tài khoản và dữ liệu",
                      ),
                      onTap: isWorking ? null : deleteAccount,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      guest
                          ? tr(
                              "Guest medication data stays on this device until you upgrade or sign in.",
                              "Dữ liệu thuốc của khách ở trên thiết bị này cho đến khi bạn nâng cấp hoặc đăng nhập.",
                            )
                          : tr(
                              "Cloud sync needs an internet connection. Your most recently saved local copy remains available offline.",
                              "Đồng bộ cần kết nối mạng. Bản lưu cục bộ gần nhất vẫn dùng được khi ngoại tuyến.",
                            ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  final bool macFirebaseConfigurationNeedsUpdate;

  const _SyncStatusCard({required this.macFirebaseConfigurationNeedsUpdate});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    if (macFirebaseConfigurationNeedsUpdate) {
      const color = Color(0xFFB54708);

      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFAEB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFEC84B)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.build_circle_outlined, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      "Finish Mac cloud setup",
                      "Hoàn tất thiết lập đám mây cho Mac",
                    ),
                    style: const TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      "This app is still linked to Firebase's old Mac ID. Your local medications are safe. Complete the included ONE_TIME_FIREBASE_SETUP guide, rebuild once, then sync.",
                      "Ứng dụng vẫn liên kết với mã Firebase cũ của Mac. Thuốc lưu trên máy vẫn an toàn. Làm theo hướng dẫn ONE_TIME_FIREBASE_SETUP đi kèm, dựng lại một lần, rồi đồng bộ.",
                    ),
                    style: const TextStyle(
                      color: Color(0xFF7A2E0E),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ValueListenableBuilder<MedicationSyncStatus>(
      valueListenable: MedicationStorage.syncStatus,
      builder: (context, status, child) {
        late final IconData icon;
        late final Color color;
        late final String label;

        switch (status.state) {
          case MedicationSyncState.syncing:
            icon = Icons.sync_rounded;
            color = AppTheme.primaryColor;
            label = tr("Syncing changes...", "Đang đồng bộ thay đổi...");
            break;
          case MedicationSyncState.synced:
            icon = Icons.cloud_done_rounded;
            color = const Color(0xFF22C55E);
            label = tr("Cloud is up to date", "Đám mây đã cập nhật");
            break;
          case MedicationSyncState.offline:
            icon = Icons.cloud_queue_rounded;
            color = AppTheme.primaryColor;
            label = tr(
              "Saved on this device — sync will retry",
              "Đã lưu trên thiết bị — sẽ thử đồng bộ lại",
            );
            break;
          case MedicationSyncState.error:
            icon = Icons.error_outline_rounded;
            color = const Color(0xFFEF4444);
            label = tr("Sync needs attention", "Đồng bộ cần kiểm tra");
            break;
          case MedicationSyncState.idle:
            icon = Icons.cloud_queue_rounded;
            color = const Color(0xFF667085);
            label = tr("Ready to sync", "Sẵn sàng đồng bộ");
            break;
        }

        final lastSync = status.lastSyncedAt;
        final detail =
            status.state == MedicationSyncState.error ||
                status.state == MedicationSyncState.offline
            ? MedicationStorage.syncFailureMessage(
                vietnamese: AppLanguage.currentLanguage.value == "vi",
              )
            : lastSync == null
            ? null
            : "${tr("Last synced", "Đồng bộ lần cuối")} ${TimeHelper.formatDateTimeAsDisplayTime(lastSync)}";

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.86),
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccountActionCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _AccountActionCard({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppTheme.primaryColor;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ?? Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
