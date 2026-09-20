import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'pill_box_service.dart';

class PillBoxPage extends StatefulWidget {
  const PillBoxPage({super.key});

  @override
  State<PillBoxPage> createState() => _PillBoxPageState();
}

class _PillBoxPageState extends State<PillBoxPage> {
  final PillBoxService service = PillBoxService();
  final TextEditingController addressController = TextEditingController();
  int selectedSlot = 0;
  bool isSending = false;
  bool? lastRequestWorked;
  String status = '';

  String tr(String english, String vietnamese) =>
      AppLanguage.currentLanguage.value == 'en' ? english : vietnamese;

  @override
  void initState() {
    super.initState();
    loadAddress();
  }

  Future<void> loadAddress() async {
    final address = await PillBoxService.loadAddress();
    if (mounted) addressController.text = address;
  }

  Future<void> runRequest(
    Future<PillBoxResponse> Function(String address) action,
  ) async {
    FocusScope.of(context).unfocus();
    setState(() {
      isSending = true;
      status = '';
      lastRequestWorked = null;
    });

    PillBoxResponse result;
    try {
      await PillBoxService.saveAddress(addressController.text);
      result = await action(addressController.text);
    } on FormatException catch (error) {
      result = PillBoxResponse(ok: false, message: error.message.toString());
    }

    if (!mounted) return;
    setState(() {
      isSending = false;
      status = result.message;
      lastRequestWorked = result.ok;
    });
  }

  @override
  void dispose() {
    addressController.dispose();
    service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                          IconButton.filledTonal(
                            tooltip: tr('Back', 'Quay lại'),
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('Smart Pill Box', 'Hộp thuốc thông minh'),
                                  style: const TextStyle(
                                    color: AppTheme.ink,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  tr(
                                    '10 compartments · 2 rows × 5 columns',
                                    '10 ngăn · 2 hàng × 5 cột',
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
                      const SizedBox(height: 22),
                      _Notice(
                        icon: Icons.info_outline_rounded,
                        text: tr(
                          'When it is time, the assigned compartment blinks. Opening the correct lid keeps its light on. Opening a different lid makes the buzzer beep.',
                          'Đến giờ, ngăn đã gán sẽ nhấp nháy. Mở đúng nắp thì đèn sáng liên tục. Mở sai nắp thì còi sẽ kêu.',
                        ),
                      ),
                      const SizedBox(height: 18),
                      _SectionCard(
                        title: tr('1. Connect', '1. Kết nối'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: addressController,
                              enabled: !isSending,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: tr(
                                  'Arduino IP address',
                                  'Địa chỉ IP Arduino',
                                ),
                                hintText: PillBoxService.defaultAddress,
                                prefixIcon: const Icon(Icons.router_outlined),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: isSending
                                  ? null
                                  : () => runRequest(service.testConnection),
                              icon: const Icon(Icons.wifi_find_rounded),
                              label: Text(tr('Test connection', 'Thử kết nối')),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: tr(
                          '2. Choose a compartment',
                          '2. Chọn ngăn thuốc',
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 5,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: PillBoxSlot.slotCount,
                              itemBuilder: (context, index) {
                                final selected = selectedSlot == index;
                                final number = (index + 1).toString();
                                return Semantics(
                                  button: true,
                                  selected: selected,
                                  label: tr(
                                    'Compartment $number',
                                    'Ngăn $number',
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: isSending
                                        ? null
                                        : () => setState(() {
                                            selectedSlot = index;
                                          }),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppTheme.primaryColor
                                            : AppTheme.lightColor,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        number,
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : AppTheme.ink,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: isSending
                                  ? null
                                  : () => runRequest(
                                      (address) => service.lightSlot(
                                        address,
                                        selectedSlot,
                                      ),
                                    ),
                              icon: const Icon(Icons.light_mode_rounded),
                              label: Text(
                                tr(
                                  'Blink compartment ${selectedSlot + 1}',
                                  'Nhấp nháy ngăn ${selectedSlot + 1}',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: isSending
                                  ? null
                                  : () => runRequest(service.turnOff),
                              icon: const Icon(Icons.lightbulb_outline_rounded),
                              label: Text(
                                tr('Turn off reminder', 'Tắt lời nhắc'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSending) ...[
                        const SizedBox(height: 18),
                        const Center(child: CircularProgressIndicator()),
                      ],
                      if (status.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _Notice(
                          icon: lastRequestWorked == true
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          text: status,
                          success: lastRequestWorked == true,
                        ),
                      ],
                      const SizedBox(height: 18),
                      _Notice(
                        icon: Icons.medication_outlined,
                        text: tr(
                          'Assign each medication to one compartment when adding or editing it. The box can guide one medication at a time.',
                          'Gán mỗi thuốc vào một ngăn khi thêm hoặc sửa. Hộp hướng dẫn một thuốc mỗi lần.',
                        ),
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
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.success = false});

  final IconData icon;
  final String text;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF15803D) : AppTheme.primaryColor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.ink,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
