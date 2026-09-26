import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_language.dart';
import 'app_text_size.dart';
import 'app_theme.dart';
import 'apple_watch_page.dart';
import 'account_preferences_sync.dart';
import 'adherence_dashboard_page.dart';
import 'auth_page.dart';
import 'auth_service.dart';
import 'crash_reporting.dart';
import 'date_helper.dart';
import 'firebase_options.dart';
import 'in_app_guide_overlay.dart';
import 'legal_pages.dart' as legal;
import 'medication.dart';
import 'medication_list_page.dart';
import 'medication_storage.dart';
import 'notification_service.dart';
import 'notification_action_handler.dart';
import 'onboarding_service.dart';
import 'pill_box_page.dart';
import 'pill_box_reminder_bridge.dart';
import 'reminder_page.dart';
import 'reminder_reliability_page.dart';
import 'route_transitions.dart';
import 'schedule_preferences.dart';
import 'schedule_settings_page.dart';
import 'scan_page.dart';
import 'time_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedicationReminderApp());
}

class MedicationReminderApp extends StatefulWidget {
  const MedicationReminderApp({super.key});

  @override
  State<MedicationReminderApp> createState() => _MedicationReminderAppState();
}

class _MedicationReminderAppState extends State<MedicationReminderApp> {
  bool _startupComplete = false;
  bool _firebaseAvailable = false;

  @override
  void initState() {
    super.initState();
    CrashReporting.installGlobalHandlers();
    TimeHelper.applyDeviceTimeFormat(
      WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat,
    );
    unawaited(_loadLocalSettings());
    unawaited(_startLocalServices());
    unawaited(_initializeFirebase());
    unawaited(_initializeNotifications());
    PillBoxReminderBridge.start();
  }

  Future<void> _loadLocalSettings() async {
    final loaders = <Future<void> Function()>[
      AppLanguage.loadSavedLanguage,
      AppTheme.loadSavedTheme,
      AppTextSize.loadSavedTextSize,
      SchedulePreferences.load,
      CrashReporting.loadPreference,
    ];

    await Future.wait(
      loaders.map((load) async {
        try {
          await load();
        } catch (error, stackTrace) {
          debugPrint(
            'Could not load a saved app preference: $error\n$stackTrace',
          );
        }
      }),
    );
  }

  Future<void> _startLocalServices() async {
    try {
      await MedicationStorage.startExternalChangeMonitoring();
    } catch (error, stackTrace) {
      debugPrint(
        'Local medication change monitoring failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 12));
      AuthService.setFirebaseAvailable(true);

      if (!mounted) return;
      setState(() {
        _firebaseAvailable = true;
        _startupComplete = true;
      });

      unawaited(_configureFirebaseServices());
    } catch (error, stackTrace) {
      AuthService.setFirebaseAvailable(false);
      debugPrint(
        'Firebase startup failed; continuing with local data: $error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() => _startupComplete = true);
    }
  }

  Future<void> _configureFirebaseServices() async {
    try {
      await CrashReporting.configureAfterFirebase();
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleDeviceCheckProvider(),
      );
      if (kDebugMode) {
        debugPrint(
          'Firebase App Check debug mode is active. '
          'Register the debug token printed by Firebase in the App Check console.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Optional Firebase startup service failed: $error\n$stackTrace',
      );
    }

    try {
      await MedicationStorage.startCloudSyncMonitoring();
      await AccountPreferencesSync.start();
    } catch (error, stackTrace) {
      debugPrint('Cloud sync startup failed: $error\n$stackTrace');
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      NotificationService.configureNotificationResponseHandler(
        NotificationActionHandler.handle,
        backgroundHandler: medicationNotificationActionBackground,
      );
      await NotificationService.initialize();
    } catch (error, stackTrace) {
      debugPrint(
        'Notifications unavailable during startup: $error\n$stackTrace',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppTheme.currentTheme,
      builder: (context, themeValue, child) {
        return ValueListenableBuilder<String>(
          valueListenable: AppLanguage.currentLanguage,
          builder: (context, languageValue, child) {
            return ValueListenableBuilder<String>(
              valueListenable: AppTextSize.currentTextSize,
              builder: (context, textSizeValue, child) {
                return MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: "Medication Reminder",
                  theme: AppTheme.buildTheme(),
                  builder: (context, child) {
                    final mediaQuery = MediaQuery.of(context);
                    TimeHelper.applyDeviceTimeFormat(
                      mediaQuery.alwaysUse24HourFormat,
                    );

                    return MediaQuery(
                      data: mediaQuery.copyWith(
                        textScaler: TextScaler.linear(AppTextSize.scaleFactor),
                      ),
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                  home: !_startupComplete
                      ? const _AppStartupPage()
                      : _firebaseAvailable
                      ? const MedicationAuthGate()
                      : const HomePage(),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AppStartupPage extends StatelessWidget {
  const _AppStartupPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.medication_rounded,
                size: 52,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: 18),
              Text(
                AppLanguage.tr('Medication Reminder', 'Nhắc Nhở Uống Thuốc'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              CircularProgressIndicator(color: AppTheme.primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}

class MedicationAuthGate extends StatelessWidget {
  const MedicationAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: AppTheme.pageDecoration(),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              ),
            ),
          );
        }

        if (snapshot.data == null) {
          return const AuthenticationPage();
        }

        return const HomePage();
      },
    );
  }
}

class HomeDoseInfo {
  final Medication medication;
  final int medicationIndex;
  final TimeOfDay time;
  final DateTime dateTime;
  final String status;

  const HomeDoseInfo({
    required this.medication,
    required this.medicationIndex,
    required this.time,
    required this.dateTime,
    required this.status,
  });
}

typedef HomeOpenReminder =
    void Function(int medicationIndex, {DateTime? doseDateTime});

class HomeMissedDoseInfo {
  final Medication medication;
  final int medicationIndex;
  final int missedDoseCount;

  const HomeMissedDoseInfo({
    required this.medication,
    required this.medicationIndex,
    required this.missedDoseCount,
  });
}

class HomeAlertSnapshot {
  final List<HomeDoseInfo> todayDoses;
  final List<Medication> lowQuantityMedications;

  const HomeAlertSnapshot({
    required this.todayDoses,
    required this.lowQuantityMedications,
  });
}

class AppSoftBackground extends StatelessWidget {
  final Widget child;

  const AppSoftBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      height: double.infinity,
      decoration: AppTheme.pageDecoration(),
      child: child,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> medicationTabNavigatorKey =
      GlobalKey<NavigatorState>();
  final List<GlobalKey> homeNavigationGuideKeys = List<GlobalKey>.generate(
    4,
    (_) => GlobalKey(),
  );
  final GlobalKey scanCameraGuideKey = GlobalKey();
  final GlobalKey scanPhotoLibraryGuideKey = GlobalKey();
  final PageController homePageController = PageController();
  List<Medication> medications = [];
  bool isLoadingMedications = true;
  bool isRefreshingCloud = false;
  bool isOnboardingVisible = false;
  bool isOpeningReminderPage = false;
  int inAppGuideStep = 0;
  String inAppGuideUserId = "";
  bool preferredNamePromptVisible = false;
  Timer? automaticSyncTimer;
  Timer? onboardingRetryTimer;
  DateTime selectedHomeDate = DateHelper.dateOnly(DateTime.now());
  int selectedHomeTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MedicationStorage.dataRevision.addListener(refreshHomeFromLocal);
    OnboardingService.pendingUserId.addListener(handleOnboardingRequest);
    loadHomeWidget();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await promptForPreferredNameIfNeeded();

      if (mounted) {
        await restoreAndPresentOnboarding();
      }
    });
    automaticSyncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(refreshFromCloud());
    });
  }

  @override
  void dispose() {
    automaticSyncTimer?.cancel();
    onboardingRetryTimer?.cancel();
    MedicationStorage.dataRevision.removeListener(refreshHomeFromLocal);
    OnboardingService.pendingUserId.removeListener(handleOnboardingRequest);
    WidgetsBinding.instance.removeObserver(this);
    homePageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(MedicationStorage.checkForExternalDataChanges());
      final today = DateHelper.dateOnly(DateTime.now());

      if (!isSameCalendarDate(selectedHomeDate, today) && mounted) {
        setState(() {
          selectedHomeDate = today;
        });
      }

      final homeRouteIsVisible = ModalRoute.of(context)?.isCurrent ?? true;

      if (homeRouteIsVisible) {
        unawaited(refreshHomeFromLocal());
        unawaited(refreshFromCloud(forceSessionRefresh: true));
        scheduleOnboardingCheck();
      }
    }
  }

  Future<void> restoreAndPresentOnboarding() async {
    if (AuthService.isGuest) {
      await OnboardingService.requestForGuest(AuthService.userId);
    } else {
      await OnboardingService.restoreForUser(AuthService.userId);
    }
    scheduleOnboardingCheck();
  }

  void handleOnboardingRequest() {
    scheduleOnboardingCheck();
  }

  void scheduleOnboardingCheck({Duration delay = Duration.zero}) {
    if (!mounted) {
      return;
    }

    onboardingRetryTimer?.cancel();

    if (delay > Duration.zero) {
      onboardingRetryTimer = Timer(delay, () {
        if (mounted) {
          unawaited(showPendingOnboarding());
        }
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(showPendingOnboarding());
      }
    });
  }

  Future<void> showPendingOnboarding() async {
    if (!mounted || isOnboardingVisible) {
      return;
    }

    final userId = AuthService.userId;

    if (userId.isEmpty || OnboardingService.pendingUserId.value != userId) {
      return;
    }

    final routeIsVisible = ModalRoute.of(context)?.isCurrent ?? false;

    if (!routeIsVisible) {
      scheduleOnboardingCheck(delay: const Duration(milliseconds: 450));
      return;
    }

    final initialStep = await OnboardingService.loadStepForUser(
      userId,
      stepCount: InAppGuideOverlay.stepCount,
    );

    if (!mounted ||
        isOnboardingVisible ||
        OnboardingService.pendingUserId.value != userId) {
      return;
    }

    setState(() {
      isOnboardingVisible = true;
      inAppGuideStep = initialStep;
      inAppGuideUserId = userId;
    });
    await animateToHomeTab(InAppGuideOverlay.tabForStep(initialStep));
    if (mounted) setState(() {});
  }

  Future<void> advanceInAppGuide() async {
    if (!isOnboardingVisible) return;

    if (inAppGuideStep < InAppGuideOverlay.stepCount - 1) {
      final nextStep = inAppGuideStep + 1;
      setState(() => inAppGuideStep = nextStep);
      if (inAppGuideUserId.isNotEmpty) {
        unawaited(
          OnboardingService.saveStepForUser(inAppGuideUserId, nextStep),
        );
      }
      await animateToHomeTab(InAppGuideOverlay.tabForStep(nextStep));
      if (mounted) setState(() {});
      return;
    }

    await closeInAppGuide(completed: true);
  }

  Future<void> closeInAppGuide({bool completed = true}) async {
    final userId = inAppGuideUserId;
    if (!mounted) return;
    setState(() {
      isOnboardingVisible = false;
      inAppGuideStep = 0;
      inAppGuideUserId = "";
    });
    if (completed && userId.isNotEmpty) {
      await OnboardingService.completeForUser(userId);
    }
  }

  Future<void> replayInAppGuide() async {
    setState(() {
      isOnboardingVisible = true;
      inAppGuideStep = 0;
      inAppGuideUserId = "";
    });
    await animateToHomeTab(0);
    if (mounted) setState(() {});
  }

  Rect? guideTargetRectForStep(int step) {
    final GlobalKey? key = switch (step) {
      0 => homeNavigationGuideKeys[0],
      1 => homeNavigationGuideKeys[1],
      2 => scanCameraGuideKey,
      3 => scanPhotoLibraryGuideKey,
      5 => homeNavigationGuideKeys[2],
      6 => homeNavigationGuideKeys[3],
      _ => null,
    };
    final targetContext = key?.currentContext;
    final renderObject = targetContext?.findRenderObject();

    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }

    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Future<void> refreshFromCloud({bool forceSessionRefresh = false}) async {
    if (isRefreshingCloud || !MedicationStorage.canUseCloudSync) {
      return;
    }

    isRefreshingCloud = true;

    try {
      if (forceSessionRefresh) {
        try {
          await AuthService.refreshCloudSession(forceRefresh: true);
        } catch (_) {
          // MedicationStorage falls back to the safe local copy below.
        }
      }

      final loadedMedications = await MedicationStorage.loadMedications();

      if (!mounted) return;

      setState(() {
        medications = loadedMedications;
        isLoadingMedications = false;
      });

      await MedicationStorage.rescheduleAllMedicationNotifications(
        loadedMedications,
      );
    } finally {
      isRefreshingCloud = false;
    }
  }

  Future<void> refreshHomeFromLocal() async {
    final loadedMedications =
        await MedicationStorage.loadCurrentLocalMedications();

    if (!mounted) return;
    setState(() {
      medications = loadedMedications;
      isLoadingMedications = false;
    });
  }

  Future<void> loadHomeWidget() async {
    // Paint the encrypted local schedule first so Today never waits for a
    // network round trip. Cloud changes arrive through the normal revision
    // listener when synchronization finishes.
    await refreshHomeFromLocal();

    if (mounted) {
      unawaited(
        MedicationStorage.rescheduleAllMedicationNotifications(
          List<Medication>.from(medications),
        ),
      );
      unawaited(refreshFromCloud(forceSessionRefresh: true));
    }
  }

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Future<void> selectLanguage(String language) async {
    await AppLanguage.changeLanguage(language);

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> selectTheme(String theme) async {
    await AppTheme.changeTheme(theme);

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> selectTextSize(String textSize) async {
    await AppTextSize.changeTextSize(textSize);

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> openSettingsSheet() async {
    await animateToHomeTab(3);
  }

  Future<void> openAccountPage() async {
    if (!AuthService.firebaseAvailable) {
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              tr("Cloud sync unavailable", "Không thể đồng bộ đám mây"),
            ),
            content: Text(
              tr(
                "Firebase could not start. Your local medication data is still available. Check firebase_options.dart and your internet connection, then restart the app.",
                "Firebase không thể khởi động. Dữ liệu thuốc cục bộ vẫn còn. Hãy kiểm tra firebase_options.dart và kết nối mạng, rồi khởi động lại ứng dụng.",
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: Text(tr("OK", "Đồng ý")),
              ),
            ],
          );
        },
      );
      return;
    }

    await Navigator.push(
      context,
      slowPageRoute(builder: (context) => const AccountPage()),
    );

    if (mounted && AuthService.isSignedIn) {
      await loadHomeWidget();
    }
  }

  Future<void> openPrivacyPolicyPage() async {
    await Navigator.push(
      context,
      slowPageRoute(builder: (context) => const legal.LegalDocumentsPage()),
    );
  }

  Future<void> openScheduleSettingsPage() async {
    await Navigator.push(
      context,
      slowPageRoute(builder: (context) => const ScheduleSettingsPage()),
    );
    await loadHomeWidget();
  }

  Future<void> openDashboardPage() async {
    await Navigator.push(
      context,
      slowPageRoute(builder: (context) => const AdherenceDashboardPage()),
    );
    await loadHomeWidget();
  }

  Future<void> openAppleWatchPage() async {
    await Navigator.push(
      context,
      slowPageRoute(builder: (context) => const AppleWatchPage()),
    );
  }

  Future<void> chooseHomeDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: selectedHomeDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: tr("Choose a day", "Chọn ngày"),
      cancelText: tr("Cancel", "Huỷ"),
      confirmText: tr("Choose", "Chọn"),
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

    if (selectedDate == null || !mounted) {
      return;
    }

    setState(() {
      selectedHomeDate = DateHelper.dateOnly(selectedDate);
    });
  }

  Future<void> openMedicationListPage() async {
    if (!mounted) return;
    await animateToHomeTab(2);
    medicationTabNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    await MedicationStorage.checkForExternalDataChanges();
  }

  Future<void> openReminderPage(
    int medicationIndex, {
    DateTime? doseDateTime,
  }) async {
    if (isOpeningReminderPage) return;

    if (medicationIndex < 0 || medicationIndex >= medications.length) {
      await openMedicationListPage();
      return;
    }

    isOpeningReminderPage = true;
    final selectedMedication = medications[medicationIndex];
    final selectedDoseTime = doseDateTime == null
        ? null
        : TimeHelper.timeToString(TimeOfDay.fromDateTime(doseDateTime));

    if (mounted) {
      setState(() => selectedHomeTab = 2);
    }

    if (homePageController.hasClients) {
      homePageController.jumpToPage(2);
    }

    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) {
      isOpeningReminderPage = false;
      return;
    }

    try {
      await Navigator.of(context, rootNavigator: true).push(
        slowPageRoute(
          builder: (routeContext) {
            return Scaffold(
              body: ReminderPage(
                medication: selectedMedication,
                medicationIndex: medicationIndex,
                initialDoseTime: selectedDoseTime,
              ),
              bottomNavigationBar: HomeBottomNavigationBar(
                selectedIndex: 2,
                onSelected: (index) {
                  Navigator.of(routeContext, rootNavigator: true).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      unawaited(animateToHomeTab(index));
                    }
                  });
                },
              ),
            );
          },
        ),
      );
    } finally {
      isOpeningReminderPage = false;
    }

    await loadHomeWidget();
  }

  Future<void> showMissedDosePicker(
    List<HomeMissedDoseInfo> missedDoseMedications,
  ) async {
    if (missedDoseMedications.isEmpty) {
      return;
    }

    if (missedDoseMedications.length == 1) {
      await openReminderPage(missedDoseMedications.first.medicationIndex);
      return;
    }

    final selectedMedicationIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr("Choose medication", "Chọn thuốc")),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: missedDoseMedications.length,
              separatorBuilder: (context, index) {
                return const Divider(height: 1);
              },
              itemBuilder: (context, index) {
                final missedInfo = missedDoseMedications[index];
                final medication = missedInfo.medication;
                final medicationName = medication.name.trim().isEmpty
                    ? tr("Medication", "Thuốc")
                    : medication.name.trim();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFEF4444),
                  ),
                  title: Text(
                    medicationName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    tr(
                      "${missedInfo.missedDoseCount} missed dose",
                      "${missedInfo.missedDoseCount} liều bị lỡ",
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context, missedInfo.medicationIndex);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(tr("Cancel", "Huỷ")),
            ),
          ],
        );
      },
    );

    if (selectedMedicationIndex == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    await openReminderPage(selectedMedicationIndex);
  }

  int parseQuantityNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);

    if (match == null) {
      return 0;
    }

    return int.tryParse(match.group(0) ?? "") ?? 0;
  }

  int totalQuantity(Medication medication) {
    return parseQuantityNumber(medication.quantity);
  }

  int remainingQuantity(Medication medication) {
    final total = totalQuantity(medication);

    if (total <= 0) {
      return 0;
    }

    if (medication.remainingQuantity.trim().isEmpty) {
      return total;
    }

    return parseQuantityNumber(medication.remainingQuantity);
  }

  bool isOutOfMedication(Medication medication) {
    final total = totalQuantity(medication);

    if (total <= 0) {
      return false;
    }

    return remainingQuantity(medication) <= 0;
  }

  bool isLowQuantity(Medication medication) {
    final total = totalQuantity(medication);

    if (total <= 0) {
      return false;
    }

    final remaining = remainingQuantity(medication);
    final percentRemaining = remaining / total;

    return percentRemaining <= 0.05;
  }

  bool isTreatmentFinished(Medication medication) {
    final endDate = DateHelper.parseMedicationDate(medication.endDate);

    if (endDate == null) {
      return false;
    }

    return DateHelper.isBeforeToday(endDate);
  }

  DateTime getDoseDateTimeForTime(TimeOfDay time) {
    final now = DateTime.now();

    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  String doseRecordKeyForTime(TimeOfDay time) {
    final doseDateTime = getDoseDateTimeForTime(time);

    return TimeHelper.doseRecordKeyForDate(doseDateTime, time);
  }

  List<Medication> getLowQuantityMedications() {
    final lowMedications = medications.where((medication) {
      return !isTreatmentFinished(medication) && isLowQuantity(medication);
    }).toList();

    lowMedications.sort((a, b) {
      final aIsOut = isOutOfMedication(a);
      final bIsOut = isOutOfMedication(b);

      if (aIsOut && !bIsOut) {
        return -1;
      }

      if (!aIsOut && bIsOut) {
        return 1;
      }

      return 0;
    });

    return lowMedications;
  }

  String getLowQuantitySubtitle(List<Medication> lowMedications) {
    if (lowMedications.isEmpty) {
      return "";
    }

    final firstMedication = lowMedications.first;
    final name = firstMedication.name.trim().isEmpty
        ? tr("Medication", "Thuốc")
        : firstMedication.name.trim();

    final remaining = remainingQuantity(firstMedication);
    final total = totalQuantity(firstMedication);
    final isOut = isOutOfMedication(firstMedication);

    final statusText = isOut
        ? tr("$name is OUT OF MEDICINE", "$name ĐÃ HẾT THUỐC")
        : tr(
            "$name: $remaining of $total left",
            "$name: còn $remaining trên $total",
          );

    if (lowMedications.length == 1) {
      return statusText;
    }

    return tr(
      "$statusText • ${lowMedications.length - 1} more",
      "$statusText • thêm ${lowMedications.length - 1} thuốc",
    );
  }

  List<HomeMissedDoseInfo> getMissedDoseMedications() {
    final now = DateTime.now();
    final List<HomeMissedDoseInfo> missedMedications = [];

    for (int index = 0; index < medications.length; index++) {
      final medication = medications[index];

      if (isTreatmentFinished(medication)) {
        continue;
      }

      final times = getMedicationTimes(medication);
      final treatmentStartDate = DateHelper.parseMedicationDate(
        medication.startDate,
      );

      if (times.isEmpty) {
        continue;
      }

      int missedCount = 0;

      for (int timeIndex = 0; timeIndex < times.length; timeIndex++) {
        if (!TimeHelper.reminderOccursOnDate(
          times: times,
          reminderIndex: timeIndex,
          date: now,
          treatmentStartDate: treatmentStartDate,
        )) {
          continue;
        }

        final time = times[timeIndex];
        final recordKey = doseRecordKeyForTime(time);

        final savedStatus = medication.doseRecords[recordKey];

        if (savedStatus == "taken") {
          continue;
        }

        if (savedStatus == "missed" || savedStatus == "skipped") {
          missedCount++;
          continue;
        }

        final scheduledDateTime = getDoseDateTimeForTime(time);

        final endOfWindow = scheduledDateTime.add(const Duration(minutes: 120));

        if (now.isAfter(endOfWindow)) {
          missedCount++;
        }
      }

      if (missedCount > 0) {
        missedMedications.add(
          HomeMissedDoseInfo(
            medication: medication,
            medicationIndex: index,
            missedDoseCount: missedCount,
          ),
        );
      }
    }

    return missedMedications;
  }

  String getMissedDoseSubtitle(List<HomeMissedDoseInfo> missedMedications) {
    if (missedMedications.isEmpty) {
      return "";
    }

    final firstMissed = missedMedications.first;
    final name = firstMissed.medication.name.trim().isEmpty
        ? tr("Medication", "Thuốc")
        : firstMissed.medication.name.trim();

    if (missedMedications.length == 1) {
      final missedCount = firstMissed.missedDoseCount;

      return tr(
        missedCount == 1
            ? "$name has 1 dose not marked as taken."
            : "$name has $missedCount doses not marked as taken.",
        "$name có $missedCount liều chưa đánh dấu đã uống.",
      );
    }

    return tr(
      "$name and ${missedMedications.length - 1} more medications need attention.",
      "$name và ${missedMedications.length - 1} thuốc khác cần kiểm tra.",
    );
  }

  Future<bool> confirmRefillPickup(Medication medication) async {
    final name = medication.name.trim().isEmpty
        ? tr("this medication", "thuốc này")
        : medication.name.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            tr(
              "Did you already pick up the refill?",
              "Bạn đã nhận thuốc refill chưa?",
            ),
          ),
          content: Text(
            tr(
              "Only tap Yes after you already got $name from the pharmacy. The app will set the remaining quantity back to full.",
              "Chỉ bấm Có sau khi bạn đã nhận $name từ nhà thuốc. Ứng dụng sẽ đặt số lượng còn lại về đầy.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(tr("Cancel", "Huỷ")),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(
                tr("Yes, I Got It", "Có, Đã Nhận"),
                style: const TextStyle(
                  color: Color(0xFF22C55E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> markLowMedicationRefilled(Medication medication) async {
    if (medication.id.trim().isEmpty) {
      return;
    }

    final total = medication.quantity.trim();

    if (total.isEmpty || parseQuantityNumber(total) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              "Please enter total quantity first.",
              "Vui lòng nhập tổng số lượng trước.",
            ),
          ),
        ),
      );
      return;
    }

    final confirmed = await confirmRefillPickup(medication);

    if (!confirmed) {
      return;
    }

    final previousMedication = medication;
    final refilledMedication = medication.copyWith(remainingQuantity: total);

    final updated = await MedicationStorage.updateMedicationById(
      medication.id,
      refilledMedication,
    );
    await loadHomeWidget();

    if (!mounted) {
      return;
    }

    if (!updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              "This medication was removed before the refill was saved.",
              "Thuốc này đã bị xoá trước khi refill được lưu.",
            ),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            "Refill saved. Remaining quantity is full now.",
            "Đã lưu refill. Số lượng thuốc đã đầy lại.",
          ),
        ),
        action: SnackBarAction(
          label: tr("Undo", "Hoàn tác"),
          onPressed: () async {
            await MedicationStorage.updateMedicationById(
              previousMedication.id,
              previousMedication,
            );
            await loadHomeWidget();
          },
        ),
      ),
    );
  }

  List<TimeOfDay> getMedicationTimes(Medication medication) {
    if (medication.reminderTimes.isNotEmpty) {
      return medication.reminderTimes.map((time) {
        return TimeHelper.stringToTime(time);
      }).toList();
    }

    final scheduleDirections = TimeHelper.selectScheduleDirections(
      instructions: medication.instructions,
      notes: medication.notes,
    );

    return TimeHelper.generateReminderTimesFromInstructions(scheduleDirections);
  }

  List<HomeDoseInfo> getHomeDoseOptions() {
    final now = DateTime.now();
    final List<HomeDoseInfo> doseOptions = [];

    for (
      int medicationIndex = 0;
      medicationIndex < medications.length;
      medicationIndex++
    ) {
      final medication = medications[medicationIndex];

      if (isTreatmentFinished(medication)) {
        continue;
      }

      final times = getMedicationTimes(medication);
      final treatmentStartDate = DateHelper.parseMedicationDate(
        medication.startDate,
      );

      for (int timeIndex = 0; timeIndex < times.length; timeIndex++) {
        final occursToday = TimeHelper.reminderOccursOnDate(
          times: times,
          reminderIndex: timeIndex,
          date: now,
          treatmentStartDate: treatmentStartDate,
        );
        final time = times[timeIndex];

        if (!occursToday) {
          final tomorrow = DateHelper.dateOnly(
            now.add(const Duration(days: 1)),
          );
          final treatmentEndDate = DateHelper.parseMedicationDate(
            medication.endDate,
          );

          if (treatmentEndDate != null && tomorrow.isAfter(treatmentEndDate)) {
            continue;
          }

          final tomorrowDateTime = DateTime(
            tomorrow.year,
            tomorrow.month,
            tomorrow.day,
            time.hour,
            time.minute,
          );
          final tomorrowRecordKey = TimeHelper.doseRecordKeyForDate(
            tomorrowDateTime,
            time,
          );
          final tomorrowStatus = medication.doseRecords[tomorrowRecordKey];

          if (tomorrowStatus != "taken" &&
              tomorrowStatus != "missed" &&
              tomorrowStatus != "skipped") {
            doseOptions.add(
              HomeDoseInfo(
                medication: medication,
                medicationIndex: medicationIndex,
                time: time,
                dateTime: tomorrowDateTime,
                status: "scheduled",
              ),
            );
          }

          continue;
        }

        final recordKey = doseRecordKeyForTime(time);

        final savedStatus = medication.doseRecords[recordKey];

        if (savedStatus == "taken" ||
            savedStatus == "missed" ||
            savedStatus == "skipped") {
          continue;
        }

        final scheduledDateTime = getDoseDateTimeForTime(time);

        final endOfWindow = scheduledDateTime.add(const Duration(minutes: 120));

        if (now.isBefore(scheduledDateTime)) {
          doseOptions.add(
            HomeDoseInfo(
              medication: medication,
              medicationIndex: medicationIndex,
              time: time,
              dateTime: scheduledDateTime,
              status: "scheduled",
            ),
          );
        } else if (now.isBefore(endOfWindow) ||
            now.isAtSameMomentAs(endOfWindow)) {
          doseOptions.add(
            HomeDoseInfo(
              medication: medication,
              medicationIndex: medicationIndex,
              time: time,
              dateTime: scheduledDateTime,
              status: "due",
            ),
          );
        } else {
          doseOptions.add(
            HomeDoseInfo(
              medication: medication,
              medicationIndex: medicationIndex,
              time: time,
              dateTime: scheduledDateTime.add(const Duration(days: 1)),
              status: "scheduled",
            ),
          );
        }
      }
    }

    doseOptions.sort((a, b) {
      final timeCompare = a.dateTime.compareTo(b.dateTime);
      if (timeCompare != 0) {
        return timeCompare;
      }

      return a.medication.name.compareTo(b.medication.name);
    });

    return doseOptions;
  }

  List<HomeDoseInfo> getHomeDoseCardDoses() {
    final allOptions = getHomeDoseOptions();

    if (allOptions.isEmpty) {
      return [];
    }

    final dueOptions = allOptions.where((dose) {
      return dose.status == "due";
    }).toList();

    if (dueOptions.isNotEmpty) {
      return dueOptions;
    }

    final firstDose = allOptions.first;

    return allOptions.where((dose) {
      return dose.dateTime.year == firstDose.dateTime.year &&
          dose.dateTime.month == firstDose.dateTime.month &&
          dose.dateTime.day == firstDose.dateTime.day &&
          dose.dateTime.hour == firstDose.dateTime.hour &&
          dose.dateTime.minute == firstDose.dateTime.minute;
    }).toList();
  }

  bool isSameCalendarDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  bool isMedicationActiveOnDate(Medication medication, DateTime date) {
    final selectedDay = DateHelper.dateOnly(date);
    final startDate = DateHelper.parseMedicationDate(medication.startDate);
    final endDate = DateHelper.parseMedicationDate(medication.endDate);

    if (startDate != null && selectedDay.isBefore(startDate)) {
      return false;
    }

    if (endDate != null && selectedDay.isAfter(endDate)) {
      return false;
    }

    return true;
  }

  String doseRecordKeyForDate(DateTime date, TimeOfDay time) {
    return TimeHelper.doseRecordKeyForDate(date, time);
  }

  String doseStatusForDate(
    Medication medication,
    DateTime date,
    TimeOfDay time,
  ) {
    final savedStatus =
        medication.doseRecords[doseRecordKeyForDate(date, time)];

    if (savedStatus == "taken" ||
        savedStatus == "missed" ||
        savedStatus == "skipped") {
      return savedStatus!;
    }

    final now = DateTime.now();
    final scheduledDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final selectedDay = DateHelper.dateOnly(date);
    final today = DateHelper.dateOnly(now);

    if (selectedDay.isBefore(today)) {
      return "missed";
    }

    if (selectedDay.isAfter(today) || now.isBefore(scheduledDateTime)) {
      return "scheduled";
    }

    final endOfWindow = scheduledDateTime.add(const Duration(minutes: 120));

    if (!now.isAfter(endOfWindow)) {
      return "due";
    }

    return "missed";
  }

  List<HomeDoseInfo> getHomeDosesForDate(DateTime date) {
    final selectedDay = DateHelper.dateOnly(date);
    final List<HomeDoseInfo> doses = [];

    for (
      int medicationIndex = 0;
      medicationIndex < medications.length;
      medicationIndex++
    ) {
      final medication = medications[medicationIndex];

      if (!isMedicationActiveOnDate(medication, selectedDay)) {
        continue;
      }

      final times = getMedicationTimes(medication);
      final treatmentStartDate = DateHelper.parseMedicationDate(
        medication.startDate,
      );

      for (int timeIndex = 0; timeIndex < times.length; timeIndex++) {
        if (!TimeHelper.reminderOccursOnDate(
          times: times,
          reminderIndex: timeIndex,
          date: selectedDay,
          treatmentStartDate: treatmentStartDate,
        )) {
          continue;
        }

        final time = times[timeIndex];
        doses.add(
          HomeDoseInfo(
            medication: medication,
            medicationIndex: medicationIndex,
            time: time,
            dateTime: DateTime(
              selectedDay.year,
              selectedDay.month,
              selectedDay.day,
              time.hour,
              time.minute,
            ),
            status: doseStatusForDate(medication, selectedDay, time),
          ),
        );
      }
    }

    doses.sort((first, second) {
      final timeComparison = first.dateTime.compareTo(second.dateTime);

      if (timeComparison != 0) {
        return timeComparison;
      }

      return first.medication.name.compareTo(second.medication.name);
    });

    return doses;
  }

  HomeDoseInfo? getNextReminderAfterSelectedDay(DateTime selectedDate) {
    final firstSearchDay = DateHelper.dateOnly(
      selectedDate.add(const Duration(days: 1)),
    );
    HomeDoseInfo? nextDose;

    for (
      int medicationIndex = 0;
      medicationIndex < medications.length;
      medicationIndex++
    ) {
      final medication = medications[medicationIndex];
      final times = getMedicationTimes(medication);

      if (times.isEmpty) {
        continue;
      }

      var candidateDay = firstSearchDay;
      final startDate = DateHelper.parseMedicationDate(medication.startDate);
      final endDate = DateHelper.parseMedicationDate(medication.endDate);

      if (startDate != null && candidateDay.isBefore(startDate)) {
        candidateDay = startDate;
      }

      if (endDate != null && candidateDay.isAfter(endDate)) {
        continue;
      }

      for (final time in times) {
        final candidateDateTime = DateTime(
          candidateDay.year,
          candidateDay.month,
          candidateDay.day,
          time.hour,
          time.minute,
        );

        final candidate = HomeDoseInfo(
          medication: medication,
          medicationIndex: medicationIndex,
          time: time,
          dateTime: candidateDateTime,
          status: "scheduled",
        );

        if (nextDose == null ||
            candidate.dateTime.isBefore(nextDose.dateTime)) {
          nextDose = candidate;
        }
      }
    }

    return nextDose;
  }

  String get homeDisplayName {
    final user = AuthService.currentUser;
    final savedDisplayName = user?.displayName?.trim() ?? "";

    if (savedDisplayName.isNotEmpty) {
      return savedDisplayName;
    }

    if (user?.isAnonymous ?? false) {
      return tr("Guest", "Khách");
    }

    final emailName = (user?.email ?? "").split("@").first.trim();

    if (emailName.isEmpty) {
      return tr("Welcome", "Xin chào");
    }

    final words = emailName
        .split(RegExp(r'[._-]+'))
        .where((word) => word.trim().isNotEmpty)
        .take(2)
        .map((word) {
          final cleanWord = word.replaceAll(RegExp(r'\d+$'), "");
          final value = cleanWord.isEmpty ? word : cleanWord;

          if (value.length == 1) {
            return value.toUpperCase();
          }

          return "${value[0].toUpperCase()}${value.substring(1)}";
        })
        .join(" ");

    return words.isEmpty ? tr("Welcome", "Xin chào") : words;
  }

  String get homeGreeting {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return tr("Good morning", "Chào buổi sáng");
    }

    if (hour < 18) {
      return tr("Good afternoon", "Chào buổi chiều");
    }

    return tr("Good evening", "Chào buổi tối");
  }

  Future<void> promptForPreferredNameIfNeeded() async {
    final user = AuthService.currentUser;

    if (!mounted ||
        preferredNamePromptVisible ||
        user == null ||
        user.isAnonymous ||
        (user.displayName?.trim().isNotEmpty ?? false)) {
      return;
    }

    preferredNamePromptVisible = true;
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            icon: Icon(Icons.waving_hand_rounded, color: AppTheme.primaryColor),
            title: Text(
              tr(
                "What should we call you?",
                "Bạn muốn chúng tôi gọi bạn là gì?",
              ),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: tr("Preferred name", "Tên muốn được gọi"),
                hintText: tr("Example: Phong", "Ví dụ: Phong"),
                helperText: tr(
                  "We’ll use this in your greeting.",
                  "Tên này sẽ được dùng trong lời chào.",
                ),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, value.trim());
                }
              },
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();

                  if (value.isNotEmpty) {
                    Navigator.pop(dialogContext, value);
                  }
                },
                child: Text(tr("Use this name", "Dùng tên này")),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();
    preferredNamePromptVisible = false;

    if (name == null || name.isEmpty) {
      return;
    }

    try {
      await AuthService.updatePreferredName(name);

      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                "We couldn’t save your name. Please try again in Account.",
                "Không thể lưu tên. Vui lòng thử lại trong mục Tài khoản.",
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> openHomeAlerts(
    List<HomeDoseInfo> todayDoses,
    List<Medication> lowQuantityMedications,
  ) async {
    await Navigator.of(context).push<void>(
      slowPageRoute(
        builder: (alertsContext) {
          return HomeAlertsPage(
            todayDoses: todayDoses,
            lowQuantityMedications: lowQuantityMedications,
            onReload: reloadHomeAlertSnapshot,
            onOpenMedications: () {
              Navigator.of(alertsContext).pop();
              unawaited(openMedicationListPage());
            },
            onOpenDose: (dose) async {
              Navigator.of(alertsContext).pop();
              await WidgetsBinding.instance.endOfFrame;
              await openReminderPage(
                dose.medicationIndex,
                doseDateTime: dose.dateTime,
              );
            },
          );
        },
      ),
    );

    if (mounted) {
      await loadHomeWidget();
    }
  }

  HomeAlertSnapshot currentHomeAlertSnapshot() {
    return HomeAlertSnapshot(
      todayDoses: getHomeDosesForDate(DateTime.now()),
      lowQuantityMedications: getLowQuantityMedications(),
    );
  }

  Future<HomeAlertSnapshot> reloadHomeAlertSnapshot() async {
    await refreshHomeFromLocal();
    return currentHomeAlertSnapshot();
  }

  Future<void> animateToHomeTab(int index) async {
    if (!mounted || index < 0 || index > 3) {
      return;
    }

    setState(() {
      selectedHomeTab = index;

      if (index == 0) {
        selectedHomeDate = DateHelper.dateOnly(DateTime.now());
      }
    });

    await WidgetsBinding.instance.endOfFrame;

    if (!mounted || !homePageController.hasClients) {
      return;
    }

    await homePageController.animateToPage(
      index,
      duration: slowRouteTransitionDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void handleHomeNavigation(int index) {
    if (index == selectedHomeTab) {
      if (index == 0) {
        setState(() {
          selectedHomeDate = DateHelper.dateOnly(DateTime.now());
        });
      } else if (index == 2) {
        medicationTabNavigatorKey.currentState?.popUntil(
          (route) => route.isFirst,
        );
      }
      return;
    }

    unawaited(animateToHomeTab(index));
    unawaited(MedicationStorage.checkForExternalDataChanges());
  }

  Future<void> handleMedicationSavedFromScanAdd() async {
    await refreshHomeFromLocal();
    await animateToHomeTab(2);
  }

  Widget buildTodayTab() {
    final selectedDateDoses = getHomeDosesForDate(selectedHomeDate);
    final todayDoses = getHomeDosesForDate(DateTime.now());
    final nextReminder = getNextReminderAfterSelectedDay(selectedHomeDate);
    final lowQuantityMedications = getLowQuantityMedications();
    final attentionDoseCount = todayDoses.where((dose) {
      return dose.status == "missed" || dose.status == "due";
    }).length;
    final alertCount = attentionDoseCount + lowQuantityMedications.length;

    return AppSoftBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.primaryColor,
          edgeOffset: 64,
          onRefresh: loadHomeWidget,
          child: ListView(
            key: const PageStorageKey<String>("today-page-scroll"),
            primary: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              36 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
                        child: Text(
                          "$homeGreeting, $homeDisplayName",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF172033),
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      HomeCalendarHeader(
                        selectedDate: selectedHomeDate,
                        alertCount: alertCount,
                        onChooseDate: chooseHomeDate,
                        onOpenAccount: openAccountPage,
                        onOpenAlerts: () {
                          openHomeAlerts(todayDoses, lowQuantityMedications);
                        },
                      ),
                      const SizedBox(height: 12),
                      HomeWeekCalendar(
                        selectedDate: selectedHomeDate,
                        onSelected: (date) {
                          setState(() {
                            selectedHomeDate = DateHelper.dateOnly(date);
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      ValueListenableBuilder<MedicationSyncStatus>(
                        valueListenable: MedicationStorage.syncStatus,
                        builder: (context, syncStatus, child) {
                          final needsAttention =
                              MedicationStorage.canUseCloudSync &&
                              syncStatus.state == MedicationSyncState.error;

                          if (!needsAttention) {
                            return const SizedBox.shrink();
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: HomeCloudSyncBanner(onTap: openAccountPage),
                          );
                        },
                      ),
                      HomeNextDoseHero(
                        isLoading: isLoadingMedications,
                        selectedDate: selectedHomeDate,
                        doses: selectedDateDoses,
                        nextReminder: nextReminder,
                        onOpenReminder: openReminderPage,
                        onAddPrescription: () {
                          unawaited(animateToHomeTab(1));
                        },
                      ),
                      const SizedBox(height: 14),
                      HomeCalendarDayOverview(
                        isLoading: isLoadingMedications,
                        selectedDate: selectedHomeDate,
                        doses: selectedDateDoses,
                        nextReminder: nextReminder,
                        onOpenReminder: openReminderPage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF4F7FB),
          body: PageView(
            controller: homePageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) {
              if (selectedHomeTab != index) {
                setState(() {
                  selectedHomeTab = index;
                });
              }
            },
            children: [
              buildTodayTab(),
              ScanPage(
                embeddedInHomeShell: true,
                onMedicationSaved: handleMedicationSavedFromScanAdd,
                cameraGuideTargetKey: scanCameraGuideKey,
                photoLibraryGuideTargetKey: scanPhotoLibraryGuideKey,
              ),
              Navigator(
                key: medicationTabNavigatorKey,
                onGenerateRoute: (settings) {
                  return slowPageRoute<void>(
                    settings: settings,
                    builder: (context) {
                      return MedicationListPage(
                        embeddedInHomeShell: true,
                        onOpenScanAdd: () {
                          unawaited(animateToHomeTab(1));
                        },
                      );
                    },
                  );
                },
              ),
              HomeSettingsSheet(
                embeddedInHomeShell: true,
                onSelectLanguage: selectLanguage,
                onSelectTheme: selectTheme,
                onSelectTextSize: selectTextSize,
                onOpenAccount: openAccountPage,
                onOpenSchedule: openScheduleSettingsPage,
                onOpenDashboard: openDashboardPage,
                onOpenAppleWatch: openAppleWatchPage,
                onOpenPrivacy: openPrivacyPolicyPage,
                onStartGuide: replayInAppGuide,
              ),
            ],
          ),
          bottomNavigationBar: HomeBottomNavigationBar(
            selectedIndex: selectedHomeTab,
            onSelected: handleHomeNavigation,
            guideKeys: homeNavigationGuideKeys,
          ),
        ),
        if (isOnboardingVisible)
          InAppGuideOverlay(
            step: inAppGuideStep,
            targetRect: guideTargetRectForStep(inAppGuideStep),
            onNext: () => unawaited(advanceInAppGuide()),
            onClose: () => unawaited(closeInAppGuide()),
          ),
      ],
    );
  }
}

class HomeAlertsPage extends StatefulWidget {
  final List<HomeDoseInfo> todayDoses;
  final List<Medication> lowQuantityMedications;
  final Future<HomeAlertSnapshot> Function() onReload;
  final VoidCallback onOpenMedications;
  final Future<void> Function(HomeDoseInfo dose) onOpenDose;

  const HomeAlertsPage({
    super.key,
    required this.todayDoses,
    required this.lowQuantityMedications,
    required this.onReload,
    required this.onOpenMedications,
    required this.onOpenDose,
  });

  @override
  State<HomeAlertsPage> createState() => _HomeAlertsPageState();
}

class _HomeAlertsPageState extends State<HomeAlertsPage> {
  late List<HomeDoseInfo> todayDoses;
  late List<Medication> lowQuantityMedications;
  bool isReloading = false;

  @override
  void initState() {
    super.initState();
    todayDoses = [...widget.todayDoses];
    lowQuantityMedications = [...widget.lowQuantityMedications];
    MedicationStorage.dataRevision.addListener(reloadAlerts);
  }

  @override
  void dispose() {
    MedicationStorage.dataRevision.removeListener(reloadAlerts);
    super.dispose();
  }

  Future<void> reloadAlerts() async {
    if (isReloading) return;
    isReloading = true;

    try {
      final snapshot = await widget.onReload();

      if (!mounted) return;
      setState(() {
        todayDoses = [...snapshot.todayDoses];
        lowQuantityMedications = [...snapshot.lowQuantityMedications];
      });
    } finally {
      isReloading = false;
    }
  }

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  int parseQuantityNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return int.tryParse(match?.group(0) ?? "") ?? 0;
  }

  int remainingQuantity(Medication medication) {
    final total = parseQuantityNumber(medication.quantity);

    if (total <= 0) {
      return 0;
    }

    if (medication.remainingQuantity.trim().isEmpty) {
      return total;
    }

    return parseQuantityNumber(medication.remainingQuantity);
  }

  Future<void> openReminder(HomeDoseInfo dose) async {
    await widget.onOpenDose(dose);
  }

  Widget sectionHeader(String title, int count) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF172033),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.lightColor,
            borderRadius: BorderRadius.circular(99),
          ),
          alignment: Alignment.center,
          child: Text(
            "$count",
            style: TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget summaryCard({
    required int attentionCount,
    required int totalDoseCount,
    required int takenCount,
    required int upcomingCount,
  }) {
    final hasAttention = attentionCount > 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: hasAttention ? const Color(0xFFFFF7F7) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: hasAttention
              ? const Color(0xFFFECACA)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: hasAttention
                  ? const Color(0xFFFFE4E6)
                  : const Color(0xFFECFDF3),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              hasAttention
                  ? Icons.notifications_active_outlined
                  : Icons.check_circle_outline_rounded,
              color: hasAttention
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF16A34A),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasAttention
                      ? tr(
                          attentionCount == 1
                              ? "1 item needs attention"
                              : "$attentionCount items need attention",
                          "$attentionCount mục cần kiểm tra",
                        )
                      : tr("You’re all caught up", "Mọi thứ đã ổn"),
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  totalDoseCount == 0
                      ? tr(
                          "No medication reminders scheduled today",
                          "Hôm nay không có lịch nhắc thuốc",
                        )
                      : tr(
                          "$takenCount taken • $upcomingCount coming up",
                          "$takenCount đã uống • $upcomingCount sắp tới",
                        ),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget refillTile(Medication medication) {
    final name = medication.name.trim().isEmpty
        ? tr("Medication", "Thuốc")
        : medication.name.trim();
    final total = parseQuantityNumber(medication.quantity);
    final remaining = remainingQuantity(medication);
    final isOut = total > 0 && remaining <= 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenMedications,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFFEA580C),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF172033),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isOut
                          ? tr("Out of medication", "Đã hết thuốc")
                          : tr(
                              "$remaining of $total remaining",
                              "Còn $remaining trên $total",
                            ),
                      style: const TextStyle(
                        color: Color(0xFFEA580C),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget allDoneCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.spa_outlined, color: Color(0xFF16A34A), size: 42),
          const SizedBox(height: 12),
          Text(
            tr("Nothing else needs your attention", "Không còn gì cần xử lý"),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF172033),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            tr(
              "You’re up to date. We’ll let you know when the next dose needs you.",
              "Mọi thứ đã cập nhật. Chúng tôi sẽ nhắc khi đến liều tiếp theo.",
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attentionDoses =
        todayDoses.where((dose) {
          return dose.status == "missed" || dose.status == "due";
        }).toList()..sort((first, second) {
          if (first.status != second.status) {
            return first.status == "due" ? -1 : 1;
          }

          return first.dateTime.compareTo(second.dateTime);
        });
    final attentionCount = attentionDoses.length;
    final totalAttentionCount = attentionCount + lowQuantityMedications.length;
    final takenCount = todayDoses.where((dose) {
      return dose.status == "taken";
    }).length;
    final upcomingDoses =
        todayDoses.where((dose) {
          return dose.status == "scheduled";
        }).toList()..sort((first, second) {
          return first.dateTime.compareTo(second.dateTime);
        });
    final nextDose = upcomingDoses.isEmpty ? null : upcomingDoses.first;
    final hasAnyAlert =
        attentionDoses.isNotEmpty || lowQuantityMedications.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          tr("Today at a glance", "Tổng quan hôm nay"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF172033),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: AppSoftBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      summaryCard(
                        attentionCount: totalAttentionCount,
                        totalDoseCount: todayDoses.length,
                        takenCount: takenCount,
                        upcomingCount: upcomingDoses.length,
                      ),
                      const SizedBox(height: 18),
                      if (nextDose != null) ...[
                        sectionHeader(tr("Coming up", "Sắp tới"), 1),
                        const SizedBox(height: 10),
                        HomeTimelineDoseTile(
                          dose: nextDose,
                          onTap: () {
                            openReminder(nextDose);
                          },
                        ),
                        if (hasAnyAlert) const SizedBox(height: 20),
                      ],
                      if (hasAnyAlert) ...[
                        if (attentionDoses.isNotEmpty) ...[
                          sectionHeader(
                            tr("Dose alerts", "Cảnh báo liều thuốc"),
                            attentionDoses.length,
                          ),
                          const SizedBox(height: 10),
                          for (
                            var index = 0;
                            index < attentionDoses.length;
                            index++
                          )
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index == attentionDoses.length - 1
                                    ? 0
                                    : 9,
                              ),
                              child: HomeTimelineDoseTile(
                                dose: attentionDoses[index],
                                onTap: () {
                                  openReminder(attentionDoses[index]);
                                },
                              ),
                            ),
                        ],
                        if (lowQuantityMedications.isNotEmpty) ...[
                          if (attentionDoses.isNotEmpty)
                            const SizedBox(height: 20),
                          sectionHeader(
                            tr("Refill reminders", "Nhắc refill thuốc"),
                            lowQuantityMedications.length,
                          ),
                          const SizedBox(height: 10),
                          for (
                            var index = 0;
                            index < lowQuantityMedications.length;
                            index++
                          )
                            Padding(
                              padding: EdgeInsets.only(
                                bottom:
                                    index == lowQuantityMedications.length - 1
                                    ? 0
                                    : 9,
                              ),
                              child: refillTile(lowQuantityMedications[index]),
                            ),
                        ],
                      ] else if (nextDose == null)
                        allDoneCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeCalendarHeader extends StatelessWidget {
  final DateTime selectedDate;
  final int alertCount;
  final VoidCallback onChooseDate;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenAccount;

  const HomeCalendarHeader({
    super.key,
    required this.selectedDate,
    required this.alertCount,
    required this.onChooseDate,
    required this.onOpenAlerts,
    required this.onOpenAccount,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  String monthTitle() {
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

    if (AppLanguage.currentLanguage.value == "en") {
      return "${months[selectedDate.month - 1]} ${selectedDate.year}";
    }

    return "Tháng ${selectedDate.month}, ${selectedDate.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onChooseDate,
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        monthTitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF172033),
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        HeaderActionButton(
          tooltip: tr("Today’s care summary", "Tổng quan chăm sóc hôm nay"),
          icon: alertCount > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
          badgeCount: alertCount,
          attentionPulse: alertCount > 0,
          onTap: onOpenAlerts,
        ),
        const SizedBox(width: 8),
        HeaderActionButton(
          tooltip: tr("Account", "Tài khoản"),
          icon: Icons.person_outline_rounded,
          onTap: onOpenAccount,
        ),
      ],
    );
  }
}

class HomeProfileHeader extends StatelessWidget {
  final String displayName;
  final int alertCount;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenAlerts;
  final VoidCallback onAddPrescription;

  const HomeProfileHeader({
    super.key,
    required this.displayName,
    required this.alertCount,
    required this.onOpenAccount,
    required this.onOpenAlerts,
    required this.onAddPrescription,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  String greetingText() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return tr("Good morning", "Chào buổi sáng");
    }

    if (hour < 18) {
      return tr("Good afternoon", "Chào buổi chiều");
    }

    return tr("Good evening", "Chào buổi tối");
  }

  String todayText() {
    final now = DateTime.now();

    if (AppLanguage.currentLanguage.value == "en") {
      return "${HomeWeekCalendar.englishWeekdays[now.weekday - 1]}, "
          "${HomeWeekCalendar.englishMonths[now.month - 1]} ${now.day}";
    }

    return "${HomeWeekCalendar.vietnameseWeekdays[now.weekday - 1]}, "
        "${now.day} Thg ${now.month}";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${greetingText()}, $displayName",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 24,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    todayText(),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            HeaderActionButton(
              tooltip: tr("Alerts", "Cảnh báo"),
              icon: Icons.notifications_none_rounded,
              badgeCount: alertCount,
              onTap: onOpenAlerts,
            ),
            const SizedBox(width: 8),
            HeaderActionButton(
              tooltip: tr("Open account", "Mở tài khoản"),
              icon: Icons.person_outline_rounded,
              onTap: onOpenAccount,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onAddPrescription,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.document_scanner_outlined,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr("Add a medication", "Thêm thuốc mới"),
                          style: const TextStyle(
                            color: Color(0xFF172033),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tr(
                            "Scan the prescription or enter it yourself",
                            "Quét toa thuốc hoặc tự nhập thông tin",
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: AppTheme.primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class HeaderActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final int badgeCount;
  final bool attentionPulse;
  final VoidCallback onTap;

  const HeaderActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.badgeCount = 0,
    this.attentionPulse = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: attentionPulse
          ? const Duration(milliseconds: 900)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, pulseProgress, child) {
        return SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (attentionPulse)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Transform.scale(
                      scale: 0.84 + (pulseProgress * 0.42),
                      child: Opacity(
                        opacity: 1 - pulseProgress,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.22,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Material(
                  color: attentionPulse
                      ? AppTheme.lightColor.withValues(alpha: 0.92)
                      : Colors.white,
                  shape: const CircleBorder(),
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    tooltip: tooltip,
                    onPressed: onTap,
                    icon: Icon(
                      icon,
                      color: attentionPulse
                          ? AppTheme.primaryColor
                          : const Color(0xFF334155),
                      size: 24,
                    ),
                  ),
                ),
              ),
              if (badgeCount > 0)
                Positioned(
                  right: -1,
                  top: -1,
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 19,
                        minHeight: 19,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: const Color(0xFFF8FAFC),
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeCount > 9 ? "9+" : "$badgeCount",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class HomeWeekCalendar extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;

  const HomeWeekCalendar({
    super.key,
    required this.selectedDate,
    required this.onSelected,
  });

  static const List<String> englishWeekdays = [
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat",
    "Sun",
  ];

  static const List<String> vietnameseWeekdays = [
    "T2",
    "T3",
    "T4",
    "T5",
    "T6",
    "T7",
    "CN",
  ];

  static const List<String> englishMonths = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];

  bool isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String weekdayName(DateTime date) {
    final names = AppLanguage.currentLanguage.value == "en"
        ? englishWeekdays
        : vietnameseWeekdays;

    return names[date.weekday - 1];
  }

  String selectedDateTitle(DateTime date) {
    final isEnglish = AppLanguage.currentLanguage.value == "en";
    final today = DateHelper.dateOnly(DateTime.now());
    final isToday = isSameDate(date, today);

    if (isEnglish) {
      final prefix = isToday ? "Today" : weekdayName(date);
      return "$prefix, ${englishMonths[date.month - 1]} ${date.day}";
    }

    final prefix = isToday ? "Hôm nay" : weekdayName(date);
    return "$prefix, ${date.day} Thg ${date.month}";
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = DateHelper.dateOnly(selectedDate);
    final daysFromSunday = selectedDay.weekday % 7;
    final weekStart = selectedDay.subtract(Duration(days: daysFromSunday));
    final weekDates = List<DateTime>.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemGap = constraints.maxWidth < 420 ? 2.0 : 5.0;

          return Row(
            children: [
              for (var index = 0; index < weekDates.length; index++) ...[
                if (index > 0) SizedBox(width: itemGap),
                Expanded(
                  child: HomeWeekDayButton(
                    date: weekDates[index],
                    weekday: weekdayName(weekDates[index]),
                    selected: isSameDate(weekDates[index], selectedDay),
                    isToday: isSameDate(weekDates[index], DateTime.now()),
                    onTap: () {
                      onSelected(weekDates[index]);
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class HomeWeekDayButton extends StatelessWidget {
  final DateTime date;
  final String weekday;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  const HomeWeekDayButton({
    super.key,
    required this.date,
    required this.weekday,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: "$weekday ${date.day}",
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primaryColor : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppTheme.primaryColor : Colors.transparent,
              ),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      weekday,
                      maxLines: 1,
                      style: TextStyle(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.86)
                            : const Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${date.day}",
                      maxLines: 1,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFF172033),
                        fontSize: 18,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 190),
                      opacity: isToday ? 1 : 0,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white
                              : AppTheme.primaryColor,
                          shape: BoxShape.circle,
                        ),
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

class HomeCloudSyncBanner extends StatelessWidget {
  final VoidCallback onTap;

  const HomeCloudSyncBanner({super.key, required this.onTap});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.lightColor,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.cloud_sync_rounded,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr(
                    "Cloud sync is paused. Your phone data is safe. Tap to retry.",
                    "Đồng bộ đang tạm dừng. Dữ liệu trên điện thoại vẫn an toàn. Nhấn để thử lại.",
                  ),
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: AppTheme.primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeNextDoseHero extends StatelessWidget {
  final bool isLoading;
  final DateTime selectedDate;
  final List<HomeDoseInfo> doses;
  final HomeDoseInfo? nextReminder;
  final HomeOpenReminder onOpenReminder;
  final VoidCallback onAddPrescription;

  const HomeNextDoseHero({
    super.key,
    required this.isLoading,
    required this.selectedDate,
    required this.doses,
    required this.nextReminder,
    required this.onOpenReminder,
    required this.onAddPrescription,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  bool isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  HomeDoseInfo? featuredDose() {
    for (final dose in doses) {
      if (dose.status == "due") {
        return dose;
      }
    }

    for (final dose in doses) {
      if (dose.status == "scheduled") {
        return dose;
      }
    }

    for (final dose in doses) {
      if (dose.status == "missed") {
        return dose;
      }
    }

    if (doses.isNotEmpty) {
      return doses.first;
    }

    return nextReminder;
  }

  String eyebrowText(HomeDoseInfo? dose) {
    if (dose == null) {
      return tr("YOUR NEXT STEP", "BƯỚC TIẾP THEO");
    }

    if (dose.status == "due") {
      return tr("DUE NOW", "ĐẾN GIỜ UỐNG");
    }

    if (dose.status == "missed") {
      return tr("NEEDS ATTENTION", "CẦN KIỂM TRA");
    }

    if (dose.status == "taken" || dose.status == "skipped") {
      return tr("DOSE STATUS", "TRẠNG THÁI LIỀU");
    }

    final doseDay = DateHelper.dateOnly(dose.dateTime);
    final selectedDay = DateHelper.dateOnly(selectedDate);

    if (isSameDate(doseDay, selectedDay)) {
      return tr("NEXT ON THIS DAY", "LIỀU TIẾP THEO");
    }

    return tr("COMING UP", "SẮP TỚI");
  }

  String supportingText(HomeDoseInfo dose) {
    final dosage = dose.medication.dosage.trim();
    final instructions = dose.medication.instructions.trim();

    if (dosage.isNotEmpty && instructions.isNotEmpty) {
      return "$dosage • $instructions";
    }

    if (dosage.isNotEmpty) {
      return dosage;
    }

    if (instructions.isNotEmpty) {
      return instructions;
    }

    return tr("Tap to review this reminder", "Nhấn để xem nhắc nhở");
  }

  @override
  Widget build(BuildContext context) {
    final dose = featuredDose();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: isLoading
          ? SizedBox(
              height: 126,
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              ),
            )
          : Stack(
              children: [
                Positioned(
                  right: -20,
                  top: -24,
                  child: Icon(
                    Icons.medication_outlined,
                    color: AppTheme.primaryColor.withValues(alpha: 0.07),
                    size: 132,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrowText(dose),
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 12,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (dose == null) ...[
                      Text(
                        tr("No reminder scheduled", "Chưa có nhắc nhở"),
                        style: const TextStyle(
                          color: Color(0xFF172033),
                          fontSize: 24,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          "Add your first medication to start a simple daily plan.",
                          "Thêm thuốc đầu tiên để bắt đầu lịch uống hằng ngày.",
                        ),
                        style: TextStyle(
                          color: const Color(0xFF64748B),
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onAddPrescription,
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(
                          tr("Add medication", "Thêm thuốc"),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ] else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  TimeHelper.formatTimeForDisplay(dose.time),
                                  style: const TextStyle(
                                    color: Color(0xFF172033),
                                    fontSize: 34,
                                    height: 1.0,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 9),
                                Text(
                                  dose.medication.name.trim().isEmpty
                                      ? tr("Medication", "Thuốc")
                                      : dose.medication.name.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF172033),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  supportingText(dose),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: const Color(0xFF64748B),
                                    fontSize: 13,
                                    height: 1.3,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Material(
                            color: AppTheme.lightColor,
                            borderRadius: BorderRadius.circular(18),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                onOpenReminder(
                                  dose.medicationIndex,
                                  doseDateTime: dose.dateTime,
                                );
                              },
                              child: SizedBox(
                                width: 58,
                                height: 58,
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: AppTheme.primaryColor,
                                  size: 27,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

class HomeQuickActions extends StatelessWidget {
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenSchedule;

  const HomeQuickActions({
    super.key,
    required this.onOpenDashboard,
    required this.onOpenSchedule,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: HomeQuickActionCard(
            icon: Icons.insights_outlined,
            label: tr("Progress", "Tiến độ"),
            onTap: onOpenDashboard,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: HomeQuickActionCard(
            icon: Icons.schedule_rounded,
            label: tr("My schedule", "Lịch cá nhân"),
            onTap: onOpenSchedule,
          ),
        ),
      ],
    );
  }
}

class HomeQuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const HomeQuickActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.lightColor,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppTheme.primaryColor, size: 22),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeCalendarDayOverview extends StatefulWidget {
  final bool isLoading;
  final DateTime selectedDate;
  final List<HomeDoseInfo> doses;
  final HomeDoseInfo? nextReminder;
  final HomeOpenReminder onOpenReminder;

  const HomeCalendarDayOverview({
    super.key,
    required this.isLoading,
    required this.selectedDate,
    required this.doses,
    required this.nextReminder,
    required this.onOpenReminder,
  });

  @override
  State<HomeCalendarDayOverview> createState() =>
      _HomeCalendarDayOverviewState();
}

class _HomeCalendarDayOverviewState extends State<HomeCalendarDayOverview> {
  bool showTimeline = true;

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  bool isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String dateTitle() {
    const englishWeekdays = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday",
    ];
    const vietnameseWeekdays = [
      "Thứ Hai",
      "Thứ Ba",
      "Thứ Tư",
      "Thứ Năm",
      "Thứ Sáu",
      "Thứ Bảy",
      "Chủ Nhật",
    ];
    final isToday = isSameDate(widget.selectedDate, DateTime.now());

    if (AppLanguage.currentLanguage.value == "en") {
      final prefix = isToday
          ? "Today"
          : englishWeekdays[widget.selectedDate.weekday - 1];

      return "$prefix, ${HomeWeekCalendar.englishMonths[widget.selectedDate.month - 1]} "
          "${widget.selectedDate.day}";
    }

    final prefix = isToday
        ? "Hôm nay"
        : vietnameseWeekdays[widget.selectedDate.weekday - 1];

    return "$prefix, ${widget.selectedDate.day} Thg ${widget.selectedDate.month}";
  }

  String emptyMessage() {
    final reminder = widget.nextReminder;

    if (reminder == null) {
      return tr(
        "There are no medication reminders on this day.",
        "Không có nhắc thuốc trong ngày này.",
      );
    }

    final name = reminder.medication.name.trim().isEmpty
        ? tr("Medication", "Thuốc")
        : reminder.medication.name.trim();
    final date = reminder.dateTime;
    final dateText = AppLanguage.currentLanguage.value == "en"
        ? "${HomeWeekCalendar.englishMonths[date.month - 1]} ${date.day}"
        : "${date.day} Thg ${date.month}";

    return tr(
      "Next: $name on $dateText at "
          "${TimeHelper.formatTimeForDisplay(reminder.time)}.",
      "Tiếp theo: $name vào $dateText lúc "
          "${TimeHelper.formatTimeForDisplay(reminder.time)}.",
    );
  }

  @override
  Widget build(BuildContext context) {
    final usePageScrollingTimeline = MediaQuery.sizeOf(context).width < 640;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 16, 17, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateTitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF172033),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        !widget.isLoading && widget.doses.isEmpty
                            ? emptyMessage()
                            : showTimeline
                            ? tr(
                                "Detailed 24-hour timeline",
                                "Dòng thời gian chi tiết 24 giờ",
                              )
                            : tr(
                                "A simple list for this day",
                                "Danh sách đơn giản trong ngày",
                              ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  constraints: const BoxConstraints(minWidth: 34),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.lightColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "${widget.doses.length}",
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: HomeDayViewButton(
                      selected: !showTimeline,
                      icon: Icons.view_agenda_outlined,
                      label: tr("Simple", "Đơn giản"),
                      onTap: () {
                        if (showTimeline) {
                          setState(() => showTimeline = false);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: HomeDayViewButton(
                      selected: showTimeline,
                      icon: Icons.schedule_rounded,
                      label: tr("Timeline", "Dòng giờ"),
                      onTap: () {
                        if (!showTimeline) {
                          setState(() => showTimeline = true);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: showTimeline
                ? HomeHourlyMedicationTimeline(
                    key: const ValueKey<String>("timeline"),
                    selectedDate: widget.selectedDate,
                    doses: widget.doses,
                    isLoading: widget.isLoading,
                    usePageScroll: usePageScrollingTimeline,
                    onOpenReminder: widget.onOpenReminder,
                  )
                : HomeCompactMedicationTimeline(
                    key: const ValueKey<String>("simple-list"),
                    doses: widget.doses,
                    isLoading: widget.isLoading,
                    onOpenReminder: widget.onOpenReminder,
                  ),
          ),
        ],
      ),
    );
  }
}

class HomeDayViewButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const HomeDayViewButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? AppTheme.primaryColor
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF172033)
                        : const Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeCompactMedicationTimeline extends StatelessWidget {
  final List<HomeDoseInfo> doses;
  final bool isLoading;
  final HomeOpenReminder onOpenReminder;

  const HomeCompactMedicationTimeline({
    super.key,
    required this.doses,
    required this.isLoading,
    required this.onOpenReminder,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: 170,
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    final sortedDoses = [...doses]
      ..sort((first, second) => first.dateTime.compareTo(second.dateTime));

    if (sortedDoses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 30),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.lightColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.event_available_rounded,
                color: AppTheme.primaryColor,
                size: 29,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                "No doses scheduled for this day",
                "Không có liều thuốc trong ngày này",
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 14, 18),
      child: Column(
        children: [
          for (var index = 0; index < sortedDoses.length; index++) ...[
            HomeTimelineDoseTile(
              dose: sortedDoses[index],
              onTap: () {
                onOpenReminder(
                  sortedDoses[index].medicationIndex,
                  doseDateTime: sortedDoses[index].dateTime,
                );
              },
            ),
            if (index != sortedDoses.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _HomeTimelinePlacement {
  final HomeDoseInfo dose;
  final int startMinute;
  final int lane;
  int laneCount = 1;

  _HomeTimelinePlacement({
    required this.dose,
    required this.startMinute,
    required this.lane,
  });
}

class HomeHourlyMedicationTimeline extends StatefulWidget {
  final DateTime selectedDate;
  final List<HomeDoseInfo> doses;
  final bool isLoading;
  final bool usePageScroll;
  final HomeOpenReminder onOpenReminder;

  const HomeHourlyMedicationTimeline({
    super.key,
    required this.selectedDate,
    required this.doses,
    required this.isLoading,
    required this.usePageScroll,
    required this.onOpenReminder,
  });

  @override
  State<HomeHourlyMedicationTimeline> createState() =>
      _HomeHourlyMedicationTimelineState();
}

class _HomeHourlyMedicationTimelineState
    extends State<HomeHourlyMedicationTimeline> {
  static const double hourHeight = 78;
  static const double timeLabelWidth = 66;
  static const double topTimePadding = 18;
  static const double eventHeight = 64;
  static const int eventOverlapMinutes = 50;

  final ScrollController scrollController = ScrollController();
  Timer? currentTimeTimer;
  DateTime currentTime = DateTime.now();
  int scrollGeneration = 0;

  @override
  void initState() {
    super.initState();
    currentTimeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        currentTime = DateTime.now();
      });
    });

    if (!widget.usePageScroll) {
      scheduleInitialScroll();
    }
  }

  @override
  void didUpdateWidget(covariant HomeHourlyMedicationTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);

    final dateChanged = !isSameDate(
      oldWidget.selectedDate,
      widget.selectedDate,
    );
    final becameReady = oldWidget.isLoading && !widget.isLoading;
    final doseTimesChanged =
        doseTimeSignature(oldWidget.doses) != doseTimeSignature(widget.doses);

    if (!widget.usePageScroll &&
        (oldWidget.usePageScroll ||
            dateChanged ||
            becameReady ||
            doseTimesChanged)) {
      scheduleInitialScroll();
    }
  }

  String doseTimeSignature(List<HomeDoseInfo> doses) {
    return doses
        .map((dose) => "${dose.time.hour}:${dose.time.minute}")
        .join("|");
  }

  bool isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  void scheduleInitialScroll() {
    final generation = ++scrollGeneration;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != scrollGeneration) {
        return;
      }

      scrollNearRelevantTime();
    });
  }

  void scrollNearRelevantTime() {
    if (!scrollController.hasClients) {
      return;
    }

    late final int targetMinute;

    if (isSameDate(widget.selectedDate, DateTime.now())) {
      final now = DateTime.now();
      targetMinute = (now.hour * 60 + now.minute - 120).clamp(0, 1440).toInt();
    } else if (widget.doses.isNotEmpty) {
      var earliestMinute = 1440;

      for (final dose in widget.doses) {
        final minute = dose.time.hour * 60 + dose.time.minute;

        if (minute < earliestMinute) {
          earliestMinute = minute;
        }
      }

      targetMinute = (earliestMinute - 60).clamp(0, 1440).toInt();
    } else {
      targetMinute = 7 * 60;
    }

    final desiredOffset = topTimePadding + (targetMinute / 60) * hourHeight;
    final safeOffset = desiredOffset
        .clamp(0.0, scrollController.position.maxScrollExtent)
        .toDouble();

    scrollController.jumpTo(safeOffset);
  }

  List<_HomeTimelinePlacement> buildPlacements() {
    final sortedDoses = [...widget.doses]
      ..sort((first, second) {
        final firstMinute = first.time.hour * 60 + first.time.minute;
        final secondMinute = second.time.hour * 60 + second.time.minute;
        return firstMinute.compareTo(secondMinute);
      });
    final placements = <_HomeTimelinePlacement>[];
    final currentGroup = <_HomeTimelinePlacement>[];
    final laneEndMinutes = <int>[];
    var currentGroupEndMinute = -1;

    void finishCurrentGroup() {
      if (currentGroup.isEmpty) {
        return;
      }

      var laneCount = 1;

      for (final placement in currentGroup) {
        final usedLaneCount = placement.lane + 1;

        if (usedLaneCount > laneCount) {
          laneCount = usedLaneCount;
        }
      }

      for (final placement in currentGroup) {
        placement.laneCount = laneCount;
      }

      currentGroup.clear();
      laneEndMinutes.clear();
      currentGroupEndMinute = -1;
    }

    for (final dose in sortedDoses) {
      final startMinute = dose.time.hour * 60 + dose.time.minute;
      final endMinute = startMinute + eventOverlapMinutes;

      if (currentGroup.isNotEmpty && startMinute >= currentGroupEndMinute) {
        finishCurrentGroup();
      }

      var lane = -1;

      for (var index = 0; index < laneEndMinutes.length; index++) {
        if (laneEndMinutes[index] <= startMinute) {
          lane = index;
          break;
        }
      }

      if (lane < 0) {
        lane = laneEndMinutes.length;
        laneEndMinutes.add(endMinute);
      } else {
        laneEndMinutes[lane] = endMinute;
      }

      final placement = _HomeTimelinePlacement(
        dose: dose,
        startMinute: startMinute,
        lane: lane,
      );
      placements.add(placement);
      currentGroup.add(placement);

      if (endMinute > currentGroupEndMinute) {
        currentGroupEndMinute = endMinute;
      }
    }

    finishCurrentGroup();
    return placements;
  }

  String hourLabel(int hour) {
    final normalizedHour = hour % 24;

    if (TimeHelper.uses24HourFormat) {
      return normalizedHour.toString().padLeft(2, "0");
    }

    final hour12 = normalizedHour == 0
        ? 12
        : normalizedHour > 12
        ? normalizedHour - 12
        : normalizedHour;
    final period = normalizedHour < 12 ? "AM" : "PM";
    return "$hour12 $period";
  }

  @override
  Widget build(BuildContext context) {
    final timelineHeight = topTimePadding + (24 * hourHeight) + 34;
    final viewportHeight = (MediaQuery.sizeOf(context).height - 300)
        .clamp(390.0, 720.0)
        .toDouble();
    final placements = buildPlacements();
    final showCurrentTime = isSameDate(widget.selectedDate, currentTime);
    final currentMinute = currentTime.hour * 60 + currentTime.minute;
    final currentLineTop = topTimePadding + (currentMinute / 60) * hourHeight;

    final timeline = SizedBox(
      height: timelineHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var hour = 0; hour <= 24; hour++) ...[
                Positioned(
                  left: 4,
                  top: topTimePadding + (hour * hourHeight) - 8,
                  width: timeLabelWidth - 10,
                  child: Text(
                    hourLabel(hour),
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Positioned(
                  left: timeLabelWidth,
                  right: 0,
                  top: topTimePadding + (hour * hourHeight),
                  child: const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFE7ECF2),
                  ),
                ),
              ],
              for (final placement in placements)
                Builder(
                  builder: (context) {
                    const laneGap = 4.0;
                    final availableWidth =
                        constraints.maxWidth - timeLabelWidth - 12;
                    final laneWidth =
                        (availableWidth -
                            ((placement.laneCount - 1) * laneGap)) /
                        placement.laneCount;
                    final left =
                        timeLabelWidth +
                        6 +
                        placement.lane * (laneWidth + laneGap);
                    final top =
                        topTimePadding +
                        (placement.startMinute / 60) * hourHeight +
                        3;

                    return Positioned(
                      left: left,
                      top: top,
                      width: laneWidth,
                      height: eventHeight,
                      child: HomeHourlyMedicationEvent(
                        dose: placement.dose,
                        onTap: () {
                          widget.onOpenReminder(
                            placement.dose.medicationIndex,
                            doseDateTime: placement.dose.dateTime,
                          );
                        },
                      ),
                    );
                  },
                ),
              if (showCurrentTime) ...[
                Positioned(
                  left: 4,
                  top: currentLineTop - 12,
                  width: timeLabelWidth - 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        TimeHelper.formatTimeForDisplay(
                          TimeOfDay.fromDateTime(currentTime),
                        ),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: timeLabelWidth - 1,
                  right: 0,
                  top: currentLineTop,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    Widget timelineBody;

    if (widget.usePageScroll) {
      timelineBody = timeline;
    } else {
      timelineBody = Scrollbar(
        controller: scrollController,
        child: SingleChildScrollView(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          child: timeline,
        ),
      );
    }

    return SizedBox(
      height: widget.usePageScroll ? timelineHeight : viewportHeight,
      child: Stack(
        children: [
          timelineBody,
          if (widget.isLoading)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.white.withValues(alpha: 0.78),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    currentTimeTimer?.cancel();
    scrollController.dispose();
    super.dispose();
  }
}

class HomeHourlyMedicationEvent extends StatelessWidget {
  final HomeDoseInfo dose;
  final VoidCallback onTap;

  const HomeHourlyMedicationEvent({
    super.key,
    required this.dose,
    required this.onTap,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Color get statusColor {
    switch (dose.status) {
      case "taken":
        return const Color(0xFF16A34A);
      case "missed":
        return const Color(0xFFDC2626);
      case "skipped":
        return const Color(0xFF64748B);
      case "due":
        return const Color(0xFFF59E0B);
      case "scheduled":
      default:
        return AppTheme.primaryColor;
    }
  }

  IconData get statusIcon {
    switch (dose.status) {
      case "taken":
        return Icons.check_circle_rounded;
      case "missed":
        return Icons.error_rounded;
      case "skipped":
        return Icons.remove_circle_outline_rounded;
      case "due":
        return Icons.notifications_active_rounded;
      case "scheduled":
      default:
        return Icons.medication_rounded;
    }
  }

  String get statusLabel {
    switch (dose.status) {
      case "taken":
        return tr("Taken", "Đã uống");
      case "missed":
        return tr("Missed", "Bỏ lỡ");
      case "skipped":
        return tr("Skipped", "Đã bỏ qua");
      case "due":
        return tr("Due", "Đến giờ");
      case "scheduled":
      default:
        return tr("Scheduled", "Đã lên lịch");
    }
  }

  @override
  Widget build(BuildContext context) {
    final medicationName = dose.medication.name.trim().isEmpty
        ? tr("Medication", "Thuốc")
        : dose.medication.name.trim();
    final details = <String>[
      TimeHelper.formatTimeForDisplay(dose.time),
      dose.medication.dosage.trim(),
    ].where((value) => value.isNotEmpty).join(" • ");

    return Semantics(
      button: true,
      label: [
        medicationName,
        details,
        statusLabel,
      ].where((value) => value.isNotEmpty).join(", "),
      hint: tr(
        "Open this medication and dose time",
        "Mở thuốc và giờ uống này",
      ),
      child: Material(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.34)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 132;
                final showStatusText = constraints.maxWidth >= 205;

                return Row(
                  children: [
                    Container(width: 4, color: statusColor),
                    SizedBox(width: compact ? 6 : 9),
                    Icon(
                      statusIcon,
                      color: statusColor,
                      size: compact ? 17 : 20,
                    ),
                    SizedBox(width: compact ? 5 : 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicationName,
                            maxLines: compact ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF172033),
                              fontSize: compact ? 11.5 : 13.5,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (!compact && details.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              details,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showStatusText) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                    ] else
                      const SizedBox(width: 6),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class HomeTimelineDoseTile extends StatelessWidget {
  final HomeDoseInfo dose;
  final VoidCallback onTap;

  const HomeTimelineDoseTile({
    super.key,
    required this.dose,
    required this.onTap,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Color get statusColor {
    switch (dose.status) {
      case "taken":
        return const Color(0xFF16A34A);
      case "missed":
        return const Color(0xFFDC2626);
      case "skipped":
        return const Color(0xFF64748B);
      case "due":
        return const Color(0xFFF59E0B);
      case "scheduled":
      default:
        return AppTheme.primaryColor;
    }
  }

  String get statusLabel {
    switch (dose.status) {
      case "taken":
        return tr("Taken", "Đã uống");
      case "missed":
        return tr("Missed", "Bỏ lỡ");
      case "skipped":
        return tr("Skipped", "Đã bỏ qua");
      case "due":
        return tr("Due now", "Đến giờ");
      case "scheduled":
      default:
        return tr("Scheduled", "Đã lên lịch");
    }
  }

  @override
  Widget build(BuildContext context) {
    final medicationName = dose.medication.name.trim().isEmpty
        ? tr("Medication", "Thuốc")
        : dose.medication.name.trim();
    final details = [
      dose.medication.dosage.trim(),
      dose.medication.instructions.trim(),
    ].where((value) => value.isNotEmpty).join(" • ");

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.only(top: 13, right: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                TimeHelper.formatTimeForDisplay(dose.time),
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 18,
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.28),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Material(
            color: statusColor.withValues(alpha: 0.075),
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF172033),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              details,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF94A3B8),
                      size: 21,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class HomeDayOverview extends StatelessWidget {
  final bool isLoading;
  final DateTime selectedDate;
  final List<HomeDoseInfo> doses;
  final HomeDoseInfo? nextReminder;
  final HomeOpenReminder onOpenReminder;
  final VoidCallback onAddPrescription;

  const HomeDayOverview({
    super.key,
    required this.isLoading,
    required this.selectedDate,
    required this.doses,
    required this.nextReminder,
    required this.onOpenReminder,
    required this.onAddPrescription,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  bool isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String emptyTitle() {
    if (isSameDate(selectedDate, DateTime.now())) {
      return tr("No meds today", "Hôm nay không có thuốc");
    }

    if (AppLanguage.currentLanguage.value == "en") {
      return "No meds on ${HomeWeekCalendar.englishWeekdays[selectedDate.weekday - 1]}";
    }

    return "Không có thuốc vào ${HomeWeekCalendar.vietnameseWeekdays[selectedDate.weekday - 1]}";
  }

  String scheduleTitle() {
    if (isSameDate(selectedDate, DateTime.now())) {
      return tr("Today’s medications", "Thuốc hôm nay");
    }

    return tr("Scheduled medications", "Thuốc đã lên lịch");
  }

  String nextReminderText() {
    final reminder = nextReminder;

    if (reminder == null) {
      return tr("No upcoming reminder", "Không có nhắc nhở sắp tới");
    }

    final reminderDate = DateHelper.dateOnly(reminder.dateTime);
    final tomorrow = DateHelper.dateOnly(
      DateTime.now().add(const Duration(days: 1)),
    );
    late final String dateText;

    if (AppLanguage.currentLanguage.value == "en") {
      dateText = isSameDate(reminderDate, tomorrow)
          ? "tomorrow, ${HomeWeekCalendar.englishMonths[reminderDate.month - 1]} "
                "${reminderDate.day}"
          : "${HomeWeekCalendar.englishWeekdays[reminderDate.weekday - 1]}, "
                "${HomeWeekCalendar.englishMonths[reminderDate.month - 1]} "
                "${reminderDate.day}";
    } else {
      dateText = isSameDate(reminderDate, tomorrow)
          ? "ngày mai, ${reminderDate.day} Thg ${reminderDate.month}"
          : "${HomeWeekCalendar.vietnameseWeekdays[reminderDate.weekday - 1]}, "
                "${reminderDate.day} Thg ${reminderDate.month}";
    }

    return tr(
      "Next reminder:\n$dateText, ${TimeHelper.formatTimeForDisplay(reminder.time)}",
      "Nhắc nhở tiếp theo:\n$dateText, ${TimeHelper.formatTimeForDisplay(reminder.time)}",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                scheduleTitle(),
                style: const TextStyle(
                  color: Color(0xFF172033),
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.lightColor,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                tr("${doses.length} doses", "${doses.length} liều"),
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isLoading)
          Container(
            height: 118,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            ),
          )
        else if (doses.isEmpty)
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onAddPrescription,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF3),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF16A34A),
                        size: 29,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            emptyTitle(),
                            style: const TextStyle(
                              color: Color(0xFF172033),
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            nextReminderText().replaceAll("\n", " "),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: AppTheme.primaryColor,
                      size: 27,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...List<Widget>.generate(doses.length, (index) {
            final dose = doses[index];

            return Padding(
              padding: EdgeInsets.only(
                bottom: index == doses.length - 1 ? 0 : 10,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.035),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: HomeScheduleDoseTile(
                  dose: dose,
                  onTap: () {
                    onOpenReminder(
                      dose.medicationIndex,
                      doseDateTime: dose.dateTime,
                    );
                  },
                ),
              ),
            );
          }),
      ],
    );
  }
}

class HomeEmptyIllustration extends StatelessWidget {
  final VoidCallback onTap;

  const HomeEmptyIllustration({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLanguage.text("addPrescription"),
      child: Material(
        color: const Color(0xFFE2E5EC),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 142,
            height: 142,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 94,
                  height: 82,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.18),
                        blurRadius: 0,
                        offset: const Offset(6, 7),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.event_note_rounded,
                    color: AppTheme.primaryColor.withValues(alpha: 0.34),
                    size: 58,
                  ),
                ),
                Positioned(
                  right: 21,
                  bottom: 22,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScheduleDoseTile extends StatelessWidget {
  final HomeDoseInfo dose;
  final VoidCallback onTap;

  const HomeScheduleDoseTile({
    super.key,
    required this.dose,
    required this.onTap,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Color get statusColor {
    switch (dose.status) {
      case "taken":
        return const Color(0xFF16A34A);
      case "missed":
        return const Color(0xFFDC2626);
      case "skipped":
        return const Color(0xFF64748B);
      case "due":
        return const Color(0xFFF59E0B);
      case "scheduled":
      default:
        return AppTheme.primaryColor;
    }
  }

  String get statusLabel {
    switch (dose.status) {
      case "taken":
        return tr("Taken", "Đã uống");
      case "missed":
        return tr("Missed", "Bỏ lỡ");
      case "skipped":
        return tr("Skipped", "Đã bỏ qua");
      case "due":
        return tr("Due now", "Đến giờ");
      case "scheduled":
      default:
        return tr("Scheduled", "Đã lên lịch");
    }
  }

  @override
  Widget build(BuildContext context) {
    final medicationName = dose.medication.name.trim().isEmpty
        ? tr("Medication", "Thuốc")
        : dose.medication.name.trim();
    final dosage = dose.medication.dosage.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      TimeHelper.formatTimeForDisplay(dose.time),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF273142),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 112),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.11),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.medication_rounded,
                      color: statusColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          medicationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF273142),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (dosage.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            dosage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF7C8799),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<GlobalKey>? guideKeys;

  const HomeBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.guideKeys,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          height: 68,
          selectedIndex: selectedIndex,
          elevation: 0,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          indicatorColor: AppTheme.lightColor,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: onSelected,
          destinations: [
            NavigationDestination(
              key: guideKeys?[0],
              icon: const Icon(Icons.today_outlined),
              selectedIcon: Icon(
                Icons.today_rounded,
                color: AppTheme.primaryColor,
              ),
              label: tr("Today", "Hôm nay"),
            ),
            NavigationDestination(
              key: guideKeys?[1],
              icon: const Icon(Icons.document_scanner_outlined),
              selectedIcon: const Icon(Icons.document_scanner_rounded),
              label: tr("Scan", "Quét"),
            ),
            NavigationDestination(
              key: guideKeys?[2],
              icon: const Icon(Icons.medication_outlined),
              selectedIcon: Icon(
                Icons.medication_rounded,
                color: AppTheme.primaryColor,
              ),
              label: tr("Medications", "Thuốc"),
            ),
            NavigationDestination(
              key: guideKeys?[3],
              icon: const Icon(Icons.tune_rounded),
              selectedIcon: Icon(
                Icons.tune_rounded,
                color: AppTheme.primaryColor,
              ),
              label: tr("Settings", "Cài đặt"),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsGearButton extends StatelessWidget {
  final VoidCallback onTap;

  const SettingsGearButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final settingsLabel = language == "en" ? "Settings" : "Cài đặt";

    return Material(
      color: AppTheme.lightColor,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: settingsLabel,
        onPressed: onTap,
        constraints: const BoxConstraints.tightFor(width: 52, height: 52),
        icon: Icon(
          Icons.settings_rounded,
          color: AppTheme.primaryColor,
          size: 27,
        ),
      ),
    );
  }
}

class HomeSettingsSheet extends StatefulWidget {
  final bool embeddedInHomeShell;
  final Future<void> Function(String language) onSelectLanguage;
  final Future<void> Function(String theme) onSelectTheme;
  final Future<void> Function(String textSize) onSelectTextSize;
  final Future<void> Function() onOpenAccount;
  final Future<void> Function() onOpenSchedule;
  final Future<void> Function() onOpenDashboard;
  final Future<void> Function() onOpenAppleWatch;
  final Future<void> Function() onOpenPrivacy;
  final Future<void> Function() onStartGuide;

  const HomeSettingsSheet({
    super.key,
    this.embeddedInHomeShell = false,
    required this.onSelectLanguage,
    required this.onSelectTheme,
    required this.onSelectTextSize,
    required this.onOpenAccount,
    required this.onOpenSchedule,
    required this.onOpenDashboard,
    required this.onOpenAppleWatch,
    required this.onOpenPrivacy,
    required this.onStartGuide,
  });

  @override
  State<HomeSettingsSheet> createState() => _HomeSettingsSheetState();
}

class _HomeSettingsSheetState extends State<HomeSettingsSheet> {
  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Future<void> selectLanguage(String language) async {
    await widget.onSelectLanguage(language);

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> selectTheme(String theme) async {
    await widget.onSelectTheme(theme);

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> selectTextSize(String textSize) async {
    await widget.onSelectTextSize(textSize);

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> openAccount() async {
    await widget.onOpenAccount();
  }

  Future<void> openSchedule() async {
    await widget.onOpenSchedule();
  }

  Future<void> openDashboard() async {
    await widget.onOpenDashboard();
  }

  Future<void> openAppleWatch() async {
    await widget.onOpenAppleWatch();
  }

  Future<void> openPrivacy() async {
    await widget.onOpenPrivacy();
  }

  Future<void> openInAppGuide() async {
    await widget.onStartGuide();
  }

  Future<void> openReminderReliability() async {
    await Navigator.push(
      context,
      slowPageRoute(builder: (context) => const ReminderReliabilityPage()),
    );
  }

  Future<void> openSmartPillBox() async {
    await Navigator.push(
      context,
      slowPageRoute(builder: (context) => const PillBoxPage()),
    );
  }

  Future<void> showChoiceSheet({
    required String title,
    required IconData icon,
    required Widget Function(BuildContext sheetContext) choicesBuilder,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.74,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.line,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.lightColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: AppTheme.primaryColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: AppTheme.ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: tr("Close", "Đóng"),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    choicesBuilder(sheetContext),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> showLanguagePicker() async {
    final language = AppLanguage.currentLanguage.value;

    await showChoiceSheet(
      title: tr("Choose language", "Chọn ngôn ngữ"),
      icon: Icons.language_rounded,
      choicesBuilder: (sheetContext) {
        return Column(
          children: [
            SettingsOptionTile(
              color: AppTheme.primaryColor,
              label: "English",
              selected: language == "en",
              onTap: () async {
                Navigator.pop(sheetContext);
                await selectLanguage("en");
              },
            ),
            SettingsOptionTile(
              color: AppTheme.primaryColor,
              label: "Tiếng Việt",
              selected: language == "vi",
              onTap: () async {
                Navigator.pop(sheetContext);
                await selectLanguage("vi");
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> showThemePicker() async {
    final selectedTheme = AppTheme.currentTheme.value;

    await showChoiceSheet(
      title: tr("Choose app color", "Chọn màu ứng dụng"),
      icon: Icons.palette_rounded,
      choicesBuilder: (sheetContext) {
        return Column(
          children: AppTheme.themes.map((theme) {
            return SettingsOptionTile(
              color: AppTheme.colorForTheme(theme),
              label: AppTheme.themeNameForTheme(theme),
              selected: selectedTheme == theme,
              onTap: () async {
                Navigator.pop(sheetContext);
                await selectTheme(theme);
              },
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> showTextSizePicker() async {
    final selectedTextSize = AppTextSize.currentTextSize.value;

    await showChoiceSheet(
      title: tr("Choose text size", "Chọn cỡ chữ"),
      icon: Icons.text_fields_rounded,
      choicesBuilder: (sheetContext) {
        return Column(
          children: AppTextSize.textSizes.map((textSize) {
            return SettingsOptionTile(
              color: AppTheme.primaryColor,
              label: AppTextSize.textSizeNameForTextSize(textSize),
              selected: selectedTextSize == textSize,
              onTap: () async {
                Navigator.pop(sheetContext);
                await selectTextSize(textSize);
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final accountSubtitle = !AuthService.firebaseAvailable
        ? tr("Saved on this device", "Đã lưu trên thiết bị")
        : AuthService.isGuest
        ? tr("Guest account · device only", "Tài khoản khách · chỉ thiết bị")
        : AuthService.userEmail;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          child: ListView(
            padding: AppTheme.pagePadding(context),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.formMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (!widget.embeddedInHomeShell) ...[
                            IconButton.filledTonal(
                              tooltip: tr("Back", "Quay lại"),
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 12),
                          ] else ...[
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppTheme.lightColor,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr("Settings", "Cài đặt"),
                                  style: const TextStyle(
                                    color: AppTheme.ink,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  tr(
                                    "Simple controls for your care and app.",
                                    "Điều khiển đơn giản cho thuốc và ứng dụng.",
                                  ),
                                  style: const TextStyle(
                                    color: AppTheme.mutedInk,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      SettingsSectionLabel(
                        text: tr("ACCOUNT & DATA", "TÀI KHOẢN & DỮ LIỆU"),
                      ),
                      const SizedBox(height: 8),
                      SettingsSectionCard(
                        children: [
                          SettingsNavigationCard(
                            icon: Icons.cloud_done_rounded,
                            title: tr(
                              "Account & Cloud Sync",
                              "Tài khoản & Đồng bộ",
                            ),
                            subtitle: accountSubtitle,
                            onTap: openAccount,
                          ),
                          SettingsNavigationCard(
                            icon: Icons.health_and_safety_rounded,
                            title: tr(
                              "Terms & Privacy",
                              "Điều khoản & Riêng tư",
                            ),
                            subtitle: tr(
                              "Review the rules and your data choices",
                              "Xem quy định và lựa chọn dữ liệu",
                            ),
                            onTap: openPrivacy,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      SettingsSectionLabel(
                        text: tr("YOUR CARE", "CHĂM SÓC CỦA BẠN"),
                      ),
                      const SizedBox(height: 8),
                      SettingsSectionCard(
                        children: [
                          SettingsNavigationCard(
                            icon: Icons.schedule_rounded,
                            title: tr("Personal Schedule", "Lịch cá nhân"),
                            subtitle: tr(
                              "Wake, meals, and bedtime",
                              "Thức dậy, bữa ăn và giờ ngủ",
                            ),
                            onTap: openSchedule,
                          ),
                          SettingsNavigationCard(
                            icon: Icons.history_rounded,
                            title: tr("Reports & History", "Báo cáo & Lịch sử"),
                            subtitle: tr(
                              "Progress, refills, and every saved dose",
                              "Tiến độ, mua thêm và mọi liều đã lưu",
                            ),
                            onTap: openDashboard,
                          ),
                          SettingsNavigationCard(
                            icon: Icons.notifications_active_outlined,
                            title: tr(
                              "Reminder Reliability",
                              "Độ tin cậy nhắc nhở",
                            ),
                            subtitle: tr(
                              "Permissions, timing, and sound test",
                              "Quyền, thời gian và kiểm tra âm thanh",
                            ),
                            onTap: openReminderReliability,
                          ),
                          SettingsNavigationCard(
                            icon: Icons.lightbulb_circle_rounded,
                            title: tr("Smart Pill Box", "Hộp thuốc thông minh"),
                            subtitle: tr(
                              "Connect and test the 7-compartment pill box",
                              "Kết nối và thử hộp thuốc 7 ngăn",
                            ),
                            onTap: openSmartPillBox,
                          ),
                          SettingsNavigationCard(
                            icon: Icons.watch_rounded,
                            title: "Apple Watch",
                            subtitle: tr(
                              "Pair, mirror reminders, and sync",
                              "Ghép đôi, phản chiếu lời nhắc và đồng bộ",
                            ),
                            onTap: openAppleWatch,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      SettingsSectionLabel(
                        text: tr("HELP & SUPPORT", "TRỢ GIÚP & HỖ TRỢ"),
                      ),
                      const SizedBox(height: 8),
                      SettingsSectionCard(
                        children: [
                          SettingsNavigationCard(
                            icon: Icons.menu_book_rounded,
                            title: tr("How to Use", "Cách sử dụng"),
                            subtitle: tr(
                              "Replay the animated guide anytime",
                              "Xem lại hướng dẫn hoạt hình bất cứ lúc nào",
                            ),
                            onTap: openInAppGuide,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      SettingsSectionLabel(
                        text: tr("APP PREFERENCES", "TÙY CHỌN ỨNG DỤNG"),
                      ),
                      const SizedBox(height: 8),
                      SettingsSectionCard(
                        children: [
                          SettingsSelectorCard(
                            icon: Icons.language_rounded,
                            title: tr("Language", "Ngôn ngữ"),
                            value: language == "en" ? "English" : "Tiếng Việt",
                            onTap: showLanguagePicker,
                          ),
                          SettingsSelectorCard(
                            icon: Icons.palette_rounded,
                            title: tr("App Color", "Màu ứng dụng"),
                            value: AppTheme.themeName,
                            valueColor: AppTheme.primaryColor,
                            onTap: showThemePicker,
                          ),
                          SettingsSelectorCard(
                            icon: Icons.text_fields_rounded,
                            title: tr("Text Size", "Cỡ chữ"),
                            value: AppTextSize.textSizeName,
                            onTap: showTextSizePicker,
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: CrashReporting.sharingEnabled,
                            builder: (context, enabled, _) {
                              return SettingsSwitchCard(
                                icon: Icons.bug_report_outlined,
                                title: tr(
                                  "Share Crash Reports",
                                  "Chia sẻ báo cáo lỗi",
                                ),
                                subtitle: tr(
                                  "Optional diagnostics without medication details",
                                  "Chẩn đoán tùy chọn, không kèm thông tin thuốc",
                                ),
                                value: enabled,
                                onChanged: (value) {
                                  unawaited(
                                    CrashReporting.setSharingEnabled(value),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeMissedDoseAlertCard extends StatelessWidget {
  final String subtitle;
  final int count;
  final VoidCallback onTap;

  const HomeMissedDoseAlertCard({
    super.key,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFEF4444);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: color.withValues(alpha: 0.30),
              width: 1.3,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: color,
                  size: 36,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr("Missed Dose Today", "Có Liều Bị Lỡ Hôm Nay"),
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      count == 1
                          ? tr(
                              "Tap to open the reminder page.",
                              "Nhấn để mở trang nhắc thuốc.",
                            )
                          : tr(
                              "Tap to choose which medication.",
                              "Nhấn để chọn thuốc cần kiểm tra.",
                            ),
                      style: const TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: color, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeRefillAlertCard extends StatelessWidget {
  final String subtitle;
  final int count;
  final bool isOutOfMedicine;
  final String pharmacyName;
  final String pharmacyPhone;
  final VoidCallback onTap;
  final VoidCallback onRefill;

  const HomeRefillAlertCard({
    super.key,
    required this.subtitle,
    required this.count,
    required this.isOutOfMedicine,
    required this.pharmacyName,
    required this.pharmacyPhone,
    required this.onTap,
    required this.onRefill,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFEF4444);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: color.withValues(alpha: isOutOfMedicine ? 0.55 : 0.35),
              width: isOutOfMedicine ? 1.8 : 1.5,
            ),
          ),
          child: Column(
            children: [
              if (isOutOfMedicine) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr("OUT OF MEDICINE", "ĐÃ HẾT THUỐC"),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      isOutOfMedicine
                          ? Icons.error_rounded
                          : Icons.local_pharmacy_rounded,
                      color: color,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOutOfMedicine
                              ? tr("Refill Needed Now", "Cần Refill Ngay")
                              : tr("Need More Medicine?", "Cần Thêm Thuốc?"),
                          style: const TextStyle(
                            color: Color(0xFF1E2A3A),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: color,
                    size: 30,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              HomePharmacyCallBox(
                count: count,
                isOutOfMedicine: isOutOfMedicine,
                pharmacyName: pharmacyName,
                pharmacyPhone: pharmacyPhone,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: onRefill,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: count == 1
                        ? const Color(0xFF22C55E)
                        : color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    count == 1
                        ? Icons.done_all_rounded
                        : Icons.list_alt_rounded,
                  ),
                  label: Text(
                    count == 1
                        ? tr("I Got My Refill", "Đã Nhận Refill")
                        : tr("View Refill List", "Xem Danh Sách Refill"),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhoneCallButton extends StatelessWidget {
  final String phoneNumber;
  final String label;
  final bool isOutOfMedicine;

  const PhoneCallButton({
    super.key,
    required this.phoneNumber,
    required this.label,
    required this.isOutOfMedicine,
  });

  String get cleanPhoneNumber {
    return phoneNumber.replaceAll(RegExp(r'[^0-9+]'), "");
  }

  Future<void> callPhone(BuildContext context) async {
    final language = AppLanguage.currentLanguage.value;

    if (cleanPhoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language == "en"
                ? "No phone number saved."
                : "Chưa lưu số điện thoại.",
          ),
        ),
      );
      return;
    }

    final uri = Uri(scheme: "tel", path: cleanPhoneNumber);

    final canCall = await canLaunchUrl(uri);

    if (!canCall) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language == "en"
                ? "This device cannot open the phone dialer."
                : "Thiết bị này không mở được trình gọi điện.",
          ),
        ),
      );
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isOutOfMedicine
        ? const Color(0xFFEF4444)
        : const Color(0xFF22C55E);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          callPhone(context);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(82),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_rounded, size: 28, color: Colors.white),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      phoneNumber,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePharmacyCallBox extends StatelessWidget {
  final int count;
  final bool isOutOfMedicine;
  final String pharmacyName;
  final String pharmacyPhone;

  const HomePharmacyCallBox({
    super.key,
    required this.count,
    required this.isOutOfMedicine,
    required this.pharmacyName,
    required this.pharmacyPhone,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    final hasName = pharmacyName.trim().isNotEmpty;
    final hasPhone = pharmacyPhone.trim().isNotEmpty;

    if (count > 1) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          isOutOfMedicine
              ? tr(
                  "At least one medicine is out. Tap View Refill List to see each saved care-provider phone number.",
                  "Có ít nhất một thuốc đã hết. Bấm Xem Danh Sách Refill để xem số cơ sở hoặc bác sĩ đã lưu cho từng thuốc.",
                )
              : tr(
                  "More than one medicine needs refill. Tap View Refill List to see each saved care-provider phone number.",
                  "Có nhiều thuốc cần refill. Bấm Xem Danh Sách Refill để xem số cơ sở hoặc bác sĩ đã lưu cho từng thuốc.",
                ),
          style: const TextStyle(
            color: Color(0xFF1E2A3A),
            height: 1.35,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (!hasName && !hasPhone) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          isOutOfMedicine
              ? tr(
                  "Medicine is out, but no care-provider phone is saved. Open this medication and tap Edit Medication Details to add it.",
                  "Thuốc đã hết, nhưng chưa lưu số cơ sở hoặc bác sĩ. Mở thuốc này rồi bấm Sửa Thông Tin Thuốc để thêm.",
                )
              : tr(
                  "No care-provider phone saved. Open this medication and tap Edit Medication Details to add it.",
                  "Chưa lưu số cơ sở hoặc bác sĩ. Mở thuốc này rồi bấm Sửa Thông Tin Thuốc để thêm.",
                ),
          style: const TextStyle(
            color: Color(0xFF1E2A3A),
            height: 1.35,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF22C55E).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOutOfMedicine
                ? tr("Call now:", "Gọi ngay:")
                : tr("Call for refill:", "Gọi refill:"),
            style: TextStyle(
              color: isOutOfMedicine
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF1E2A3A),
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (hasName) ...[
            const SizedBox(height: 9),
            Text(
              pharmacyName.trim(),
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (hasPhone) ...[
            const SizedBox(height: 12),
            PhoneCallButton(
              phoneNumber: pharmacyPhone.trim(),
              label: tr("Call Care Provider", "Gọi Cơ Sở / Bác Sĩ"),
              isOutOfMedicine: isOutOfMedicine,
            ),
          ],
          const SizedBox(height: 9),
          Text(
            tr("Ask them for a refill.", "Hỏi họ refill thuốc."),
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class TodayNextDoseWidget extends StatelessWidget {
  final bool isLoading;
  final List<HomeDoseInfo> doses;
  final VoidCallback onOpenMedications;
  final HomeOpenReminder onOpenReminder;

  const TodayNextDoseWidget({
    super.key,
    required this.isLoading,
    required this.doses,
    required this.onOpenMedications,
    required this.onOpenReminder,
  });

  String statusText(String status) {
    final language = AppLanguage.currentLanguage.value;

    if (status == "due") {
      return language == "en" ? "Due now" : "Đến giờ uống";
    }

    return language == "en" ? "Scheduled" : "Đã lên lịch";
  }

  Color statusColor(String status) {
    if (status == "due") {
      return const Color(0xFFF59E0B);
    }

    return AppTheme.primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    if (isLoading) {
      return SimpleDoseCardShell(
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: AppTheme.primaryColor,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                language == "en" ? "Loading today..." : "Đang tải hôm nay...",
                style: const TextStyle(
                  color: Color(0xFF1E2A3A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (doses.isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenMedications,
          borderRadius: BorderRadius.circular(24),
          child: SimpleDoseCardShell(
            child: Row(
              children: [
                CuteDoseIcon(
                  icon: Icons.add_rounded,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    language == "en"
                        ? "No reminders yet. Tap to add your first medication."
                        : "Chưa có giờ nhắc. Nhấn để thêm thuốc đầu tiên.",
                    style: const TextStyle(
                      color: Color(0xFF1E2A3A),
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.primaryColor),
              ],
            ),
          ),
        ),
      );
    }

    final hasDueDose = doses.any((dose) => dose.status == "due");

    if (doses.length == 1) {
      final dose = doses.first;
      final medication = dose.medication;
      final time = dose.time;
      final chipColor = statusColor(dose.status);

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            onOpenReminder(dose.medicationIndex, doseDateTime: dose.dateTime);
          },
          borderRadius: BorderRadius.circular(24),
          child: SimpleDoseCardShell(
            child: Row(
              children: [
                CuteDoseIcon(
                  icon: dose.status == "due"
                      ? Icons.notifications_active_rounded
                      : Icons.schedule_rounded,
                  color: chipColor,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        language == "en"
                            ? "Today’s next dose"
                            : "Liều tiếp theo hôm nay",
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        TimeHelper.formatTimeForDisplay(time),
                        style: const TextStyle(
                          color: Color(0xFF1E2A3A),
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        medication.name.isEmpty
                            ? (language == "en" ? "Medication" : "Thuốc")
                            : medication.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: chipColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: chipColor.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Text(
                            statusText(dose.status),
                            style: TextStyle(
                              color: chipColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.primaryColor,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SimpleDoseCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CuteDoseIcon(
                icon: hasDueDose
                    ? Icons.notifications_active_rounded
                    : Icons.schedule_rounded,
                color: hasDueDose
                    ? const Color(0xFFF59E0B)
                    : AppTheme.primaryColor,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasDueDose
                          ? (language == "en"
                                ? "${doses.length} doses due now"
                                : "${doses.length} liều đến giờ uống")
                          : (language == "en"
                                ? "${doses.length} medications at next dose"
                                : "${doses.length} thuốc ở liều tiếp theo"),
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      language == "en"
                          ? "Tap a medication to open its reminder page."
                          : "Nhấn vào từng thuốc để mở trang nhắc thuốc.",
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...doses.map((dose) {
            return HomeDoseListRow(
              dose: dose,
              onTap: () {
                onOpenReminder(
                  dose.medicationIndex,
                  doseDateTime: dose.dateTime,
                );
              },
            );
          }),
        ],
      ),
    );
  }
}

class HomeDoseListRow extends StatelessWidget {
  final HomeDoseInfo dose;
  final VoidCallback onTap;

  const HomeDoseListRow({super.key, required this.dose, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final chipColor = dose.status == "due"
        ? const Color(0xFFF59E0B)
        : AppTheme.primaryColor;

    final medicationName = dose.medication.name.trim().isEmpty
        ? (language == "en" ? "Medication" : "Thuốc")
        : dose.medication.name.trim();

    final statusLabel = dose.status == "due"
        ? (language == "en" ? "Due now" : "Đến giờ uống")
        : (language == "en" ? "Scheduled" : "Đã lên lịch");

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: dose.status == "due"
            ? const Color(0xFFF59E0B).withValues(alpha: 0.10)
            : const Color(0xFFEAF8FF).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      TimeHelper.formatTimeForDisplay(dose.time),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medicationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1E2A3A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: chipColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: chipColor.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: chipColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: AppTheme.primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SimpleDoseCardShell extends StatelessWidget {
  final Widget child;

  const SimpleDoseCardShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class CuteDoseIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const CuteDoseIcon({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFFE2F7FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}

class SettingsSectionLabel extends StatelessWidget {
  final String text;

  const SettingsSectionLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.primaryColor,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

class SettingsSectionCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsSectionCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final separatedChildren = <Widget>[];

    for (var index = 0; index < children.length; index += 1) {
      separatedChildren.add(children[index]);

      if (index < children.length - 1) {
        separatedChildren.add(
          const Divider(height: 1, indent: 72, endIndent: 14),
        );
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.045),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: separatedChildren),
    );
  }
}

class SettingsNavigationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SettingsNavigationCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.lightColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.primaryColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.mutedInk,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: AppTheme.primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSelectorCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;
  final VoidCallback onTap;

  const SettingsSelectorCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = valueColor ?? AppTheme.primaryColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.lightColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.primaryColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: AppTheme.primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSwitchCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: title,
      hint: subtitle,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.lightColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.primaryColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.mutedInk,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsOptionTile extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SettingsOptionTile({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.10)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? color.withValues(alpha: 0.45) : AppTheme.line,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? color : AppTheme.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (selected) Icon(Icons.check_circle_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePrivacyPolicyButton extends StatelessWidget {
  final VoidCallback onTap;

  const HomePrivacyPolicyButton({super.key, required this.onTap});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.privacy_tip_rounded,
                color: AppTheme.primaryColor,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr("Terms & Privacy", "Điều Khoản & Quyền Riêng Tư"),
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tr(
                        "Read the app rules and how medication data is protected.",
                        "Xem quy định ứng dụng và cách dữ liệu thuốc được bảo vệ.",
                      ),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppSoftBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: AppTheme.pagePadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTheme.pageMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr(
                        "Medication Reminder Privacy Policy",
                        "Chính Sách Riêng Tư Medication Reminder",
                      ),
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        "Effective Date: July 24, 2026",
                        "Ngày hiệu lực: 24 tháng 7, 2026",
                      ),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 22),
                    PrivacyPolicySection(
                      icon: Icons.medication_rounded,
                      title: tr(
                        "Information Stored by the App",
                        "Thông Tin Ứng Dụng Lưu",
                      ),
                      text: tr(
                        "Medication Reminder may store medication name, dosage, quantity, remaining quantity, reminder times, dose history, notes, pharmacy, doctor, clinic, or hospital name, and its phone number.",
                        "Medication Reminder có thể lưu tên thuốc, liều lượng, tổng số lượng, số lượng còn lại, giờ nhắc, lịch sử liều, ghi chú, tên nhà thuốc, bác sĩ, phòng khám hoặc bệnh viện, và số điện thoại của cơ sở đó.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.camera_alt_rounded,
                      title: tr(
                        "Camera and Photo Library",
                        "Camera và Thư Viện Ảnh",
                      ),
                      text: tr(
                        "The app uses the camera or photo library only when you choose to scan a prescription label. OCR runs on the selected image to help fill medication details. When you type at least two letters in the Medication Name field, including when correcting a scanned name, only that medication-name query is sent to the U.S. National Library of Medicine RxNorm service. Dose instructions, notes, account details, and your medication list are not sent to RxNorm.",
                        "Ứng dụng chỉ dùng camera hoặc thư viện ảnh khi bạn chọn quét nhãn thuốc. OCR xử lý ảnh đã chọn để hỗ trợ điền thông tin thuốc. Khi bạn nhập ít nhất hai ký tự trong ô Tên Thuốc, kể cả khi sửa tên đã quét, chỉ nội dung tìm kiếm tên thuốc đó được gửi đến dịch vụ RxNorm của Thư viện Y khoa Quốc gia Hoa Kỳ. Hướng dẫn liều, ghi chú, thông tin tài khoản và danh sách thuốc không được gửi đến RxNorm.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.map_outlined,
                      title: tr(
                        "Healthcare Provider Search",
                        "Tìm Cơ Sở và Bác Sĩ",
                      ),
                      text: tr(
                        "When you type in the Pharmacy / Doctor / Clinic / Hospital field, only that provider-search text is sent to Apple Maps to find matching providers, locations, addresses, and publicly listed phone numbers. Medication names, doses, instructions, notes, account details, and your medication list are not sent with the provider search. Selecting a result saves the provider name, address, and phone number in the medication record.",
                        "Khi bạn nhập trong ô Nhà Thuốc / Bác Sĩ / Phòng Khám / Bệnh Viện, chỉ nội dung tìm kiếm cơ sở hoặc bác sĩ đó được gửi đến Apple Maps để tìm kết quả phù hợp, địa chỉ và số điện thoại công khai. Tên thuốc, liều dùng, hướng dẫn, ghi chú, thông tin tài khoản và danh sách thuốc không được gửi cùng nội dung tìm kiếm. Khi chọn kết quả, hồ sơ thuốc lưu tên, địa chỉ và số điện thoại của cơ sở hoặc bác sĩ.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.phone_rounded,
                      title: tr("Care Location Phone Calls", "Gọi Cơ Sở Y Tế"),
                      text: tr(
                        "The app may open the phone dialer when you tap a saved pharmacy, doctor, clinic, or hospital phone number. The app does not place calls automatically.",
                        "Ứng dụng có thể mở trình gọi điện khi bạn bấm vào số điện thoại nhà thuốc, bác sĩ, phòng khám hoặc bệnh viện đã lưu. Ứng dụng không tự động gọi điện.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.account_circle_rounded,
                      title: tr(
                        "Accounts and Cloud Sync",
                        "Tài Khoản và Đồng Bộ Đám Mây",
                      ),
                      text: tr(
                        "The app uses Firebase Authentication. You may use an anonymous guest account or create an email account. If you create an email account, Firebase stores the email address and authentication information needed to operate the account.",
                        "Ứng dụng dùng Firebase Authentication. Bạn có thể dùng tài khoản khách ẩn danh hoặc tạo tài khoản email. Nếu tạo tài khoản email, Firebase lưu địa chỉ email và thông tin xác thực cần thiết để vận hành tài khoản.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.cloud_done_rounded,
                      title: tr(
                        "How Medication Information Is Stored",
                        "Cách Lưu Thông Tin Thuốc",
                      ),
                      text: tr(
                        "The offline medication cache is encrypted on this device with a key held in the operating-system secure key store. Guest medication data stays local. Email accounts sync separate medication and dose-history records to Cloud Firestore under the account ID. Firestore rules restrict each account to its own records, and Firebase App Check helps reject requests that do not come from a registered app. The app does not sell medication data or use it for advertising.",
                        "Bộ nhớ thuốc ngoại tuyến được mã hóa trên thiết bị bằng khóa trong kho khóa an toàn của hệ điều hành. Dữ liệu khách chỉ lưu cục bộ. Tài khoản email đồng bộ từng thuốc và lịch sử liều riêng biệt lên Cloud Firestore theo mã tài khoản. Quy tắc Firestore giới hạn mỗi tài khoản chỉ truy cập dữ liệu của mình và Firebase App Check hỗ trợ từ chối yêu cầu không đến từ ứng dụng đã đăng ký. Ứng dụng không bán dữ liệu hoặc dùng cho quảng cáo.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.share_rounded,
                      title: tr(
                        "Caregiver Export and Sharing",
                        "Xuất và Chia Sẻ với Người Chăm Sóc",
                      ),
                      text: tr(
                        "The dashboard can create a medication and adherence report. Nothing is sent automatically. The report is copied or placed into an email or message only after you choose that action and select a recipient in the device app.",
                        "Bảng theo dõi có thể tạo báo cáo thuốc và tuân thủ. Không có nội dung nào được tự động gửi. Báo cáo chỉ được sao chép hoặc đưa vào email hay tin nhắn sau khi bạn chọn thao tác và chọn người nhận trong ứng dụng của thiết bị.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.manage_accounts_rounded,
                      title: tr(
                        "Your Choices and Data Deletion",
                        "Lựa Chọn và Xóa Dữ Liệu",
                      ),
                      text: tr(
                        "You can sync manually, sign out, or permanently delete your account and its medication records from the Account & Cloud Sync screen. Deleting the app alone may not delete cloud data. Account deletion may require a recent sign-in for security.",
                        "Bạn có thể đồng bộ thủ công, đăng xuất hoặc xóa vĩnh viễn tài khoản và dữ liệu thuốc trong màn hình Tài Khoản & Đồng Bộ. Chỉ xóa ứng dụng có thể không xóa dữ liệu đám mây. Việc xóa tài khoản có thể yêu cầu đăng nhập lại gần đây để bảo mật.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.notifications_rounded,
                      title: tr("Permissions", "Quyền Truy Cập"),
                      text: tr(
                        "Camera permission is used to take prescription label photos. Photo library permission is used to choose prescription label photos. Notification permission is used to send medication reminders.",
                        "Quyền camera được dùng để chụp nhãn thuốc. Quyền thư viện ảnh được dùng để chọn ảnh nhãn thuốc. Quyền thông báo được dùng để gửi nhắc nhở uống thuốc.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.health_and_safety_rounded,
                      title: tr("Medical Disclaimer", "Miễn Trừ Y Tế"),
                      text: tr(
                        "Medication Reminder is a reminder and tracking tool only. It does not provide medical advice, diagnosis, treatment, or prescription recommendations. Always confirm medication instructions with a licensed healthcare professional.",
                        "Medication Reminder chỉ là công cụ nhắc nhở và theo dõi. Ứng dụng không cung cấp lời khuyên y tế, chẩn đoán, điều trị, hoặc khuyến nghị đơn thuốc. Luôn xác nhận hướng dẫn dùng thuốc với chuyên gia y tế có giấy phép.",
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrivacyPolicySection(
                      icon: Icons.email_rounded,
                      title: tr("Contact", "Liên Hệ"),
                      text: tr(
                        "For privacy questions, contact the app developer. Add your support email before App Store submission.",
                        "Nếu có câu hỏi về quyền riêng tư, hãy liên hệ nhà phát triển ứng dụng. Thêm email hỗ trợ trước khi gửi lên App Store.",
                      ),
                    ),
                    const SizedBox(height: 24),
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

class PrivacyPolicySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const PrivacyPolicySection({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1E2A3A),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    height: 1.4,
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
}
