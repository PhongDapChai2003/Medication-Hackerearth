import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'healthcare_place_search.dart';
import 'medication.dart';
import 'medication_details_page.dart';
import 'medication_storage.dart';
import 'rxnorm_service.dart';
import 'route_transitions.dart';
import 'smooth_action_button.dart';
import 'time_helper.dart';

String extractLabelQuantity(List<String> lines) {
  final labeledQuantity = RegExp(
    r'\b(?:q[\s._-]*t[\s._-]*y|quantity|oty|0ty)[\s:#=.\-]*([0-9oOilL]{1,4})\b',
    caseSensitive: false,
  );

  for (final line in lines) {
    final match = labeledQuantity.firstMatch(line);

    if (match == null) {
      continue;
    }

    final normalizedDigits = (match.group(1) ?? "")
        .replaceAll(RegExp(r'[oO]'), "0")
        .replaceAll(RegExp(r'[iIlL]'), "1");
    final quantity = int.tryParse(normalizedDigits);

    if (quantity != null && quantity > 0 && quantity <= 9999) {
      return quantity.toString();
    }
  }

  final reversedQuantity = RegExp(
    r'\b([0-9oOilL]{1,4})\s*(?:q[\s._-]*t[\s._-]*y|q?ty|oty|0ty)\b',
    caseSensitive: false,
  );

  for (final line in lines) {
    final match = reversedQuantity.firstMatch(line);

    if (match == null) {
      continue;
    }

    final normalizedDigits = (match.group(1) ?? "")
        .replaceAll(RegExp(r'[oO]'), "0")
        .replaceAll(RegExp(r'[iIlL]'), "1");
    final quantity = int.tryParse(normalizedDigits);

    if (quantity != null && quantity > 0 && quantity <= 9999) {
      return quantity.toString();
    }
  }

  return "";
}

String extractLabelProviderAddress(List<String> lines) {
  final streetPattern = RegExp(
    r"\b\d{2,6}\s+(?:(?:N|S|E|W|North|South|East|West)\.?\s+)?(?:[A-Za-z0-9][A-Za-z0-9.'-]*\s+){1,6}(?:St(?:reet)?|Ave(?:nue)?|Rd|Road|Blvd|Boulevard|Dr(?:ive)?|Ln|Lane|Way|Ct|Court|Pkwy|Parkway|Hwy|Highway)\.?\b",
    caseSensitive: false,
  );
  final cityStateZipPattern = RegExp(
    r"\b[A-Za-z][A-Za-z .'-]{1,40},?\s+[A-Z]{2}\s+\d{5}(?:-\d{4})?\b",
  );
  final phonePattern = RegExp(
    r'(?:\+?1[\s\-.]?)?(?:\(\d{3}\)\s*\d{3}[\s\-.]?\d{4}|\d{3}[\s\-.]\d{3}[\s\-.]\d{4})',
  );

  String cleanPart(String value) {
    return value
        .replaceAll(phonePattern, " ")
        .replaceAll(RegExp(r'\s+'), " ")
        .replaceAll(RegExp(r'^[,;:\s]+|[,;:\s]+$'), "")
        .trim();
  }

  for (int index = 0; index < lines.length; index++) {
    final line = cleanPart(lines[index]);
    final streetMatch = streetPattern.firstMatch(line);

    if (streetMatch == null) {
      continue;
    }

    final street = cleanPart(streetMatch.group(0) ?? "");

    if (street.isEmpty) {
      continue;
    }

    final sameLineRemainder = line.substring(streetMatch.end).trim();
    final sameLineCity = cityStateZipPattern.firstMatch(sameLineRemainder);

    if (sameLineCity != null) {
      return "$street, ${cleanPart(sameLineCity.group(0) ?? "")}";
    }

    for (
      int nextIndex = index + 1;
      nextIndex < lines.length && nextIndex <= index + 2;
      nextIndex++
    ) {
      final nextLine = cleanPart(lines[nextIndex]);
      final cityMatch = cityStateZipPattern.firstMatch(nextLine);

      if (cityMatch != null) {
        return "$street, ${cleanPart(cityMatch.group(0) ?? "")}";
      }
    }

    return street;
  }

  return "";
}

bool isAdministrativePrescriptionLine(String value) {
  final lower = value.toLowerCase();
  final compact = lower.replaceAll(RegExp(r'[^a-z0-9]'), "");
  final digitLike = compact
      .replaceAll(RegExp(r'[o]'), "0")
      .replaceAll(RegExp(r'[il]'), "1");

  return lower.contains("remaining") ||
      lower.contains("remain") ||
      lower.contains("refill") ||
      lower.contains("quantity") ||
      RegExp(
        r'\bq[\s._-]*t[\s._-]*y\b',
        caseSensitive: false,
      ).hasMatch(value) ||
      RegExp(
        r'\b[0-9oOilL]{1,4}\s*(?:q?ty|oty|0ty)\b',
        caseSensitive: false,
      ).hasMatch(value) ||
      RegExp(
        r'\b(?:rx|ndc|cc)\s*[#:]?',
        caseSensitive: false,
      ).hasMatch(value) ||
      RegExp(r'\d{6,}').hasMatch(digitLike);
}

String stripAdministrativePrescriptionText(String value) {
  var cleaned = value.trim().replaceAll(RegExp(r'\s+'), " ");
  final administrativeMarker = RegExp(
    r'\b(?:q[\s._-]*t[\s._-]*y|quantity|[0-9oOilL]{1,4}\s*(?:q?ty|oty|0ty)|remain(?:ing)?|refills?|rx\s*[#:]?|ndc|cc\s*[#:]?)\b.*$',
    caseSensitive: false,
  );

  cleaned = cleaned.replaceFirst(administrativeMarker, "");
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), " ").trim();
  return cleaned;
}

class ScanPage extends StatefulWidget {
  final bool openPhotoLibraryOnStart;
  final bool embeddedInHomeShell;
  final Future<void> Function()? onMedicationSaved;
  final Key? cameraGuideTargetKey;
  final Key? photoLibraryGuideTargetKey;

  const ScanPage({
    super.key,
    this.openPhotoLibraryOnStart = false,
    this.embeddedInHomeShell = false,
    this.onMedicationSaved,
    this.cameraGuideTargetKey,
    this.photoLibraryGuideTargetKey,
  });

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  static const MethodChannel nativeVisionOcrChannel = MethodChannel(
    "medication_reminder/macos_vision_ocr",
  );

  final ImagePicker imagePicker = ImagePicker();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController dosageController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController pharmacyNameController = TextEditingController();
  final TextEditingController pharmacyAddressController =
      TextEditingController();
  final TextEditingController pharmacyPhoneController = TextEditingController();
  final TextEditingController instructionsController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final FocusNode medicationNameFocusNode = FocusNode();
  final FocusNode dosageFocusNode = FocusNode();

  final List<XFile> selectedImages = [];

  bool isOpeningCamera = false;
  bool isOpeningGallery = false;
  bool isReadingText = false;
  bool showRawText = false;
  bool isSearchingRxNorm = false;

  String scannedText = "";
  int recognizedOcrLineCount = 0;
  int lowConfidenceOcrLineCount = 0;
  String rxNormSearchMessage = "";
  Map<String, String> scanEvidence = {};
  Timer? medicationSearchDebounce;
  Timer? medicationSuggestionDismissTimer;
  int medicationSearchRequest = 0;
  bool medicationSuggestionsOpen = false;
  List<RxNormSuggestion> savedMedicationSuggestions = [];
  List<RxNormSuggestion> localMedicationSuggestions = [];
  List<RxNormSuggestion> rxNormSuggestions = [];

  @override
  void initState() {
    super.initState();
    medicationNameFocusNode.addListener(handleMedicationNameFocusChanged);
    unawaited(loadSavedMedicationSuggestions());

    if (widget.openPhotoLibraryOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        unawaited(openInitialImagePicker());
      });
    }
  }

  Future<void> openInitialImagePicker() async {
    final selectedImage = await pickImageFromGallery();

    if (!selectedImage && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  bool get isOcrSupportedOnThisPlatform {
    return Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
  }

  bool get isCameraOcrSupportedOnThisPlatform {
    return Platform.isIOS || Platform.isAndroid;
  }

  void showOcrPlatformMessage() {
    if (!mounted) {
      return;
    }

    final language = AppLanguage.currentLanguage.value;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          language == "en"
              ? "Prescription OCR is available on iPhone, Android, and macOS."
              : "Quét chữ toa thuốc hỗ trợ iPhone, Android và macOS.",
        ),
      ),
    );
  }

  void showCameraPlatformMessage() {
    if (!mounted) {
      return;
    }

    final language = AppLanguage.currentLanguage.value;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          language == "en"
              ? "Camera scanning is available on iPhone and Android. On Mac, choose label photos from the library."
              : "Quét bằng camera hỗ trợ iPhone và Android. Trên Mac, hãy chọn ảnh nhãn thuốc từ thư viện.",
        ),
      ),
    );
  }

  Future<bool> pickImageFromCamera() async {
    if (!isCameraOcrSupportedOnThisPlatform) {
      showCameraPlatformMessage();
      return false;
    }

    if (isOpeningCamera || isOpeningGallery || isReadingText) {
      return false;
    }

    setState(() {
      isOpeningCamera = true;
    });

    final language = AppLanguage.currentLanguage.value;

    try {
      final image = await imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
        maxWidth: 2400,
      );

      if (image == null) {
        return false;
      }

      setState(() {
        selectedImages.add(image);
      });

      await readTextFromAllImages();
      return true;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language == "en"
                ? "Could not open camera. Please check camera permission."
                : "Không thể mở camera. Vui lòng kiểm tra quyền camera.",
          ),
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          isOpeningCamera = false;
        });
      }
    }
  }

  Future<void> showCameraGuide() async {
    final shouldStart = await Navigator.of(context).push<bool>(
      slowPageRoute(builder: (context) => const CameraScanGuidePage()),
    );

    if (shouldStart == true && mounted) {
      await pickImageFromCamera();
    }
  }

  Future<bool> pickImageFromGallery() async {
    if (!isOcrSupportedOnThisPlatform) {
      showOcrPlatformMessage();
      return false;
    }

    if (isOpeningCamera || isOpeningGallery || isReadingText) {
      return false;
    }

    setState(() {
      isOpeningGallery = true;
    });

    final language = AppLanguage.currentLanguage.value;

    try {
      final images = await imagePicker.pickMultiImage(
        imageQuality: 100,
        maxWidth: 2400,
      );

      if (images.isEmpty) {
        return false;
      }

      setState(() {
        selectedImages.addAll(images);
      });

      await readTextFromAllImages();
      return true;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language == "en"
                ? "Could not open photo library. Please check photo permission."
                : "Không thể mở thư viện ảnh. Vui lòng kiểm tra quyền ảnh.",
          ),
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          isOpeningGallery = false;
        });
      }
    }
  }

  void clearExtractedTextOnly() {
    medicationSearchDebounce?.cancel();
    medicationSearchRequest += 1;
    scannedText = "";
    recognizedOcrLineCount = 0;
    lowConfidenceOcrLineCount = 0;
    showRawText = false;
    nameController.clear();
    dosageController.clear();
    quantityController.clear();
    pharmacyNameController.clear();
    pharmacyAddressController.clear();
    pharmacyPhoneController.clear();
    instructionsController.clear();
    notesController.clear();
    scanEvidence = {};
    rxNormSearchMessage = "";
    isSearchingRxNorm = false;
    medicationSuggestionsOpen = false;
    localMedicationSuggestions = [];
    rxNormSuggestions = [];
  }

  Map<String, String> buildScanEvidence(
    MedicationExtractedInfo info,
    String rawText,
  ) {
    final lines = rawText
        .split("\n")
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith("Photo "))
        .toList();

    String findLine(String value) {
      final normalizedValue = normalizeTextForMatching(value);

      if (normalizedValue.isEmpty) return "";

      for (final line in lines) {
        final normalizedLine = normalizeTextForMatching(line);
        final probe = normalizedValue.length > 18
            ? normalizedValue.substring(0, 18)
            : normalizedValue;

        if (normalizedLine.contains(probe) ||
            normalizedValue.contains(normalizedLine)) {
          return line;
        }
      }

      return "Derived from combined OCR text";
    }

    return {
      "Medication": findLine(info.name),
      "Dosage": findLine(info.dosage),
      "Quantity": findLine(info.quantity),
      "Directions": findLine(info.instructions),
      "Pharmacy": findLine(info.pharmacyName),
      "Provider address": findLine(info.pharmacyAddress),
    }..removeWhere((key, value) => value.trim().isEmpty);
  }

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Future<void> loadSavedMedicationSuggestions() async {
    try {
      final medications = await MedicationStorage.loadCurrentLocalMedications();
      final suggestions = <RxNormSuggestion>[];
      final seen = <String>{};

      for (final medication in medications) {
        final name = medication.name.trim();
        final dosage = medication.dosage.trim();
        final key = "${name.toLowerCase()}|${dosage.toLowerCase()}";

        if (name.isEmpty || !seen.add(key)) continue;

        suggestions.add(
          RxNormSuggestion(
            name: name,
            rxcui: "",
            score: 0,
            source: "Saved medication",
            entryName: name,
            strength: dosage,
            isSavedMedication: true,
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        savedMedicationSuggestions = suggestions;
      });

      if (medicationNameFocusNode.hasFocus) {
        handleMedicationNameChanged(nameController.text);
      }
    } catch (_) {
      // On-device and live RxNorm suggestions remain available.
    }
  }

  void handleMedicationNameFocusChanged() {
    if (!mounted) return;

    medicationSuggestionDismissTimer?.cancel();

    if (!medicationNameFocusNode.hasFocus) {
      medicationSearchDebounce?.cancel();
      medicationSearchRequest += 1;

      setState(() {
        isSearchingRxNorm = false;
      });

      medicationSuggestionDismissTimer = Timer(
        const Duration(milliseconds: 240),
        () {
          if (!mounted || medicationNameFocusNode.hasFocus) {
            return;
          }

          setState(() {
            medicationSuggestionsOpen = false;
          });
        },
      );
      return;
    }

    setState(() {
      medicationSuggestionsOpen = true;
    });
    handleMedicationNameChanged(nameController.text);
  }

  void handleMedicationNameChanged(String value) {
    medicationSearchDebounce?.cancel();
    medicationSearchRequest += 1;
    final request = medicationSearchRequest;
    final cleanQuery = value.trim();

    final localSuggestions = RxNormService.findOnDeviceSuggestions(
      cleanQuery,
      savedMedications: savedMedicationSuggestions,
      maximumResults: 8,
    );

    setState(() {
      medicationSuggestionsOpen = medicationNameFocusNode.hasFocus;
      localMedicationSuggestions = localSuggestions;
      rxNormSuggestions = [];
      rxNormSearchMessage = "";
      isSearchingRxNorm = cleanQuery.length >= 2;
    });

    if (cleanQuery.length < 2) {
      return;
    }

    medicationSearchDebounce = Timer(const Duration(milliseconds: 420), () {
      unawaited(searchRxNorm(cleanQuery, request));
    });
  }

  Future<void> searchRxNorm(String query, int request) async {
    try {
      final results = await RxNormService.findMedicationNames(
        query,
        maximumResults: 12,
      );

      if (!mounted ||
          request != medicationSearchRequest ||
          nameController.text.trim() != query) {
        return;
      }

      setState(() {
        rxNormSuggestions = results;
        isSearchingRxNorm = false;
        rxNormSearchMessage = results.isEmpty
            ? tr(
                "No online match. You can keep the name from the label.",
                "Không tìm thấy tên trực tuyến. Bạn vẫn có thể giữ tên trên nhãn.",
              )
            : "";
      });
    } catch (_) {
      if (!mounted || request != medicationSearchRequest) {
        return;
      }

      setState(() {
        isSearchingRxNorm = false;
        rxNormSearchMessage = tr(
          "Online lookup is unavailable. On-device suggestions still work.",
          "Không thể tra cứu trực tuyến. Gợi ý trên thiết bị vẫn hoạt động.",
        );
      });
    }
  }

  List<RxNormSuggestion> get visibleMedicationSuggestions {
    final combined = <RxNormSuggestion>[];
    final seen = <String>{};

    for (final suggestion in [
      ...localMedicationSuggestions,
      ...rxNormSuggestions,
    ]) {
      final key = [
        suggestion.medicationName,
        suggestion.strength,
        suggestion.doseForm,
      ].join("|").toLowerCase();

      if (!seen.add(key)) continue;

      combined.add(suggestion);

      if (combined.length >= 10) {
        break;
      }
    }

    return combined;
  }

  void selectMedicationSuggestion(RxNormSuggestion suggestion) {
    medicationSearchDebounce?.cancel();
    medicationSuggestionDismissTimer?.cancel();
    medicationSearchRequest += 1;
    final selectedName = suggestion.medicationName.trim();

    if (selectedName.isEmpty) return;

    nameController.value = TextEditingValue(
      text: selectedName,
      selection: TextSelection.collapsed(offset: selectedName.length),
    );

    if (dosageController.text.trim().isEmpty &&
        suggestion.strength.trim().isNotEmpty) {
      dosageController.text = suggestion.strength.trim();
    }

    setState(() {
      medicationSuggestionsOpen = false;
      localMedicationSuggestions = [];
      rxNormSuggestions = [];
      rxNormSearchMessage = "";
      isSearchingRxNorm = false;
    });

    dosageFocusNode.requestFocus();
  }

  Future<void> readTextFromAllImages() async {
    if (!isOcrSupportedOnThisPlatform) {
      showOcrPlatformMessage();
      return;
    }

    final language = AppLanguage.currentLanguage.value;

    if (selectedImages.isEmpty) {
      setState(() {
        clearExtractedTextOnly();
      });
      return;
    }

    setState(() {
      isReadingText = true;
      scannedText = "";
      showRawText = false;
    });

    TextRecognizer? textRecognizer;

    try {
      final List<String> photoTexts = [];
      int totalRecognizedLines = 0;
      int totalLowConfidenceLines = 0;

      Future<void> readWithNativeVision() async {
        final rawResults = await nativeVisionOcrChannel
            .invokeMethod<List<dynamic>>("recognizePrescriptionImages", {
              "paths": selectedImages.map((image) => image.path).toList(),
            });

        for (int i = 0; i < (rawResults?.length ?? 0); i++) {
          final rawResult = rawResults![i];

          if (rawResult is! Map) {
            continue;
          }

          final result = Map<Object?, Object?>.from(rawResult);
          final cleanedText = (result["text"] as String? ?? "").trim();
          totalRecognizedLines += (result["lineCount"] as num?)?.toInt() ?? 0;
          totalLowConfidenceLines +=
              (result["lowConfidenceLineCount"] as num?)?.toInt() ?? 0;

          if (cleanedText.isNotEmpty) {
            photoTexts.add("Photo ${i + 1}:\n$cleanedText");
          }
        }
      }

      Future<void> readWithMlKit() async {
        final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
        textRecognizer = recognizer;

        for (int i = 0; i < selectedImages.length; i++) {
          final inputImage = InputImage.fromFilePath(selectedImages[i].path);
          final recognizedText = await recognizer.processImage(inputImage);

          for (final block in recognizedText.blocks) {
            for (final line in block.lines) {
              if (line.text.trim().isEmpty) {
                continue;
              }

              totalRecognizedLines += 1;

              final confidence = line.confidence;

              if (confidence != null && confidence < 0.65) {
                totalLowConfidenceLines += 1;
              }
            }
          }

          final cleanedText = preserveRecognizedLabelText(recognizedText);

          if (cleanedText.isNotEmpty) {
            photoTexts.add("Photo ${i + 1}:\n$cleanedText");
          }
        }
      }

      if (Platform.isIOS || Platform.isMacOS) {
        try {
          await readWithNativeVision();
        } catch (_) {
          if (!Platform.isIOS) {
            rethrow;
          }

          photoTexts.clear();
          totalRecognizedLines = 0;
          totalLowConfidenceLines = 0;
          await readWithMlKit();
        }
      } else {
        await readWithMlKit();
      }

      final combinedText = photoTexts.join("\n\n");
      final extractedInfo = extractMedicationInfo(combinedText);

      if (!mounted) return;

      setState(() {
        scannedText = combinedText;
        recognizedOcrLineCount = totalRecognizedLines;
        lowConfidenceOcrLineCount = totalLowConfidenceLines;
        nameController.text = extractedInfo.name;
        dosageController.text = extractedInfo.dosage;
        quantityController.text = extractedInfo.quantity;
        pharmacyNameController.text = extractedInfo.pharmacyName;
        pharmacyAddressController.text = extractedInfo.pharmacyAddress;
        pharmacyPhoneController.text = extractedInfo.pharmacyPhone;
        instructionsController.text = extractedInfo.instructions;
        notesController.text = extractedInfo.notes;
        scanEvidence = buildScanEvidence(extractedInfo, combinedText);
        medicationSearchDebounce?.cancel();
        medicationSearchRequest += 1;
        localMedicationSuggestions = [];
        rxNormSuggestions = [];
        rxNormSearchMessage = "";
        isSearchingRxNorm = false;
      });

      if (extractedInfo.pharmacyPhone.isNotEmpty) {
        unawaited(enrichProviderFromPhone(extractedInfo.pharmacyPhone));
      }

      if (combinedText.trim().isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              language == "en"
                  ? "No text found. Try a clearer, closer label photo."
                  : "Không tìm thấy chữ. Hãy dùng ảnh nhãn rõ và gần hơn.",
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language == "en"
                ? "Could not read text from these photos. You can still enter details manually."
                : "Không thể đọc chữ từ các ảnh này. Bạn vẫn có thể nhập thủ công.",
          ),
        ),
      );
    } finally {
      await textRecognizer?.close();

      if (mounted) {
        setState(() {
          isReadingText = false;
        });
      }
    }
  }

  String preserveRecognizedLabelText(RecognizedText recognizedText) {
    final labelLines = <String>[];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final exactLine = line.text.replaceAll(RegExp(r'[\t ]+'), " ").trim();

        if (exactLine.isNotEmpty) {
          labelLines.add(exactLine);
        }
      }
    }

    if (labelLines.isNotEmpty) {
      return labelLines.join("\n");
    }

    return recognizedText.text
        .split("\n")
        .map((line) => line.replaceAll(RegExp(r'[\t ]+'), " ").trim())
        .where((line) => line.isNotEmpty)
        .join("\n");
  }

  MedicationExtractedInfo extractMedicationInfo(String text) {
    final lines = text
        .split("\n")
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final pharmacyName = extractPharmacyName(text, lines);
    final pharmacyAddress = extractLabelProviderAddress(lines);
    final pharmacyPhone = extractPharmacyPhone(text, lines);

    String name = "";
    String dosage = "";
    String quantity = extractQuantity(lines);
    String instructions = extractBestInstructions(lines);
    String notes = "";

    if (name.isEmpty) {
      int bestScore = -999;
      int bestIndex = -1;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        if (shouldIgnoreForMedicationName(line)) {
          continue;
        }

        final cleanedName = cleanMedicationName(line);

        if (cleanedName.isEmpty) {
          continue;
        }

        final score =
            scoreMedicationNameCandidate(cleanedName) +
            scoreMedicationNamePosition(lines, i);

        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
          name = cleanedName;
        }
      }

      if (name.isNotEmpty && dosage.isEmpty && bestIndex >= 0) {
        dosage = findDosageNearLine(lines, bestIndex);
      }
    }

    if (dosage.isEmpty) {
      dosage = extractDosageFromLines(lines);
    }

    if (instructions.isEmpty) {
      instructions = extractStrongInstructionFromText(text);
    }

    notes = extractNotes(lines);

    return MedicationExtractedInfo(
      name: name,
      dosage: dosage,
      quantity: quantity,
      pharmacyName: pharmacyName,
      pharmacyAddress: pharmacyAddress,
      pharmacyPhone: pharmacyPhone,
      instructions: instructions,
      notes: notes,
    );
  }

  String normalizeTextForMatching(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9à-ỹ]'), '');
  }

  String extractPharmacyName(String text, List<String> lines) {
    final compact = normalizeTextForMatching(text);

    if (compact.contains("cvspharmacy") ||
        compact.contains("cvs") ||
        compact.contains("caremark")) {
      return "CVS Pharmacy";
    }

    if (compact.contains("walgreens")) {
      return "Walgreens Pharmacy";
    }

    if (compact.contains("riteaid")) {
      return "Rite Aid Pharmacy";
    }

    if (compact.contains("walmartpharmacy") || compact.contains("walmart")) {
      return "Walmart Pharmacy";
    }

    if (compact.contains("costcopharmacy") || compact.contains("costco")) {
      return "Costco Pharmacy";
    }

    if (compact.contains("samsclubpharmacy") || compact.contains("samsclub")) {
      return "Sam's Club Pharmacy";
    }

    if (compact.contains("targetpharmacy")) {
      return "Target Pharmacy";
    }

    if (compact.contains("safewaypharmacy") || compact.contains("safeway")) {
      return "Safeway Pharmacy";
    }

    if (compact.contains("albertsonspharmacy") ||
        compact.contains("albertsons")) {
      return "Albertsons Pharmacy";
    }

    if (compact.contains("vonspharmacy") || compact.contains("vons")) {
      return "Vons Pharmacy";
    }

    if (compact.contains("ralphspharmacy") || compact.contains("ralphs")) {
      return "Ralphs Pharmacy";
    }

    int bestScore = -999;
    String bestName = "";

    for (final line in lines) {
      final lower = line.toLowerCase();

      if (!looksLikePharmacyLine(lower)) {
        continue;
      }

      if (looksLikeBadPharmacyLine(lower)) {
        continue;
      }

      final cleaned = cleanPharmacyName(line);

      if (cleaned.isEmpty) {
        continue;
      }

      final score = scorePharmacyNameCandidate(cleaned, lower);

      if (score > bestScore) {
        bestScore = score;
        bestName = cleaned;
      }
    }

    return bestName;
  }

  bool looksLikePharmacyLine(String lower) {
    return lower.contains("pharmacy") ||
        lower.contains("pharm") ||
        lower.contains("clinic") ||
        lower.contains("medical") ||
        lower.contains("drug") ||
        lower.contains("rx center") ||
        lower.contains("prescription center");
  }

  bool looksLikeBadPharmacyLine(String lower) {
    return lower.contains("take") ||
        lower.contains("directions") ||
        lower.contains("pharmacy/clinic") ||
        lower.contains("pharmacy / clinic") ||
        lower.contains("from the") ||
        lower.contains("such as") ||
        lower.contains("search and choose") ||
        lower.contains("provider") ||
        lower.contains("label") ||
        lower.contains("patient") ||
        lower.contains("doctor") ||
        lower.contains("prescriber") ||
        lower.contains("qty") ||
        lower.contains("quantity") ||
        lower.contains("warning") ||
        lower.contains("caution") ||
        lower.contains("refill remaining") ||
        lower.contains("ndc");
  }

  int scorePharmacyNameCandidate(String value, String lower) {
    int score = 0;

    if (lower.contains("pharmacy")) {
      score += 10;
    }

    if (lower.contains("clinic")) {
      score += 8;
    }

    if (lower.contains("medical")) {
      score += 6;
    }

    if (value.length >= 5) {
      score += 2;
    }

    if (value.length > 45) {
      score -= 5;
    }

    if (RegExp(r'\d{6,}').hasMatch(value)) {
      score -= 4;
    }

    return score;
  }

  String cleanPharmacyName(String value) {
    String cleaned = value.trim();

    cleaned = cleaned.replaceAll(
      RegExp(
        r'(\+?1[\s\-.]?)?(\(\d{3}\)\s*\d{3}[\s\-.]?\d{4}|\d{3}[\s\-.]\d{3}[\s\-.]\d{4})',
      ),
      "",
    );

    cleaned = cleaned.replaceAll(
      RegExp(r'Photo\s+\d+\s*:', caseSensitive: false),
      "",
    );

    cleaned = cleaned.replaceAll(
      RegExp(r'\b(phone|tel|fax)\b\s*[:#]?', caseSensitive: false),
      "",
    );

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), " ").trim();

    final lower = cleaned.toLowerCase();

    if (lower.contains("cvs")) {
      return "CVS Pharmacy";
    }

    if (lower.contains("walgreens")) {
      return "Walgreens Pharmacy";
    }

    if (lower.contains("rite aid")) {
      return "Rite Aid Pharmacy";
    }

    if (lower.contains("walmart")) {
      return "Walmart Pharmacy";
    }

    if (lower.contains("costco")) {
      return "Costco Pharmacy";
    }

    if (lower.contains("safeway")) {
      return "Safeway Pharmacy";
    }

    if (lower.contains("albertsons")) {
      return "Albertsons Pharmacy";
    }

    if (lower.contains("vons")) {
      return "Vons Pharmacy";
    }

    if (lower.contains("ralphs")) {
      return "Ralphs Pharmacy";
    }

    if (cleaned.length > 55) {
      cleaned = cleaned.substring(0, 55).trim();
    }

    return cleaned;
  }

  String extractPharmacyPhone(String text, List<String> lines) {
    final phoneRegExp = RegExp(
      r'(\+?1[\s\-.]?)?(\(\d{3}\)\s*\d{3}[\s\-.]?\d{4}|\d{3}[\s\-.]\d{3}[\s\-.]\d{4})',
    );

    final candidates = <PhoneCandidate>[];

    for (final line in lines) {
      final lower = line.toLowerCase();

      for (final match in phoneRegExp.allMatches(line)) {
        final rawPhone = match.group(0) ?? "";
        final phone = formatPhoneNumber(rawPhone);

        if (phone.isEmpty) {
          continue;
        }

        candidates.add(
          PhoneCandidate(phone: phone, score: scorePhoneCandidate(lower)),
        );
      }

      if (lower.contains("phone") ||
          lower.contains("tel") ||
          lower.contains("pharmacy") ||
          lower.contains("clinic")) {
        final digitsOnly = line.replaceAll(RegExp(r'[^0-9]'), "");

        if (digitsOnly.length == 10 ||
            (digitsOnly.length == 11 && digitsOnly.startsWith("1"))) {
          final phone = formatPhoneNumber(digitsOnly);

          if (phone.isNotEmpty) {
            candidates.add(
              PhoneCandidate(
                phone: phone,
                score: scorePhoneCandidate(lower) + 2,
              ),
            );
          }
        }
      }
    }

    if (candidates.isEmpty) {
      return "";
    }

    candidates.sort((a, b) {
      return b.score.compareTo(a.score);
    });

    return candidates.first.phone;
  }

  String phoneDigits(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), "");

    if (digits.length == 11 && digits.startsWith("1")) {
      digits = digits.substring(1);
    }

    return digits;
  }

  Future<void> enrichProviderFromPhone(String phone) async {
    final expectedDigits = phoneDigits(phone);

    if (expectedDigits.length != 10) {
      return;
    }

    HealthcarePlaceSuggestion? exactMatch;

    try {
      final savedMedications =
          await MedicationStorage.loadCurrentLocalMedications();

      for (final medication in savedMedications) {
        if (phoneDigits(medication.pharmacyPhone) == expectedDigits &&
            medication.pharmacyName.trim().isNotEmpty) {
          exactMatch = HealthcarePlaceSuggestion(
            name: medication.pharmacyName.trim(),
            address: medication.pharmacyAddress.trim(),
            phone: medication.pharmacyPhone.trim(),
            source: HealthcarePlaceSource.saved,
          );
          break;
        }
      }

      if (exactMatch == null) {
        final results = await HealthcarePlaceService.searchAppleMaps(
          phone,
          maximumResults: 10,
        );

        for (final place in results) {
          if (phoneDigits(place.phone) == expectedDigits) {
            exactMatch = place;
            break;
          }
        }
      }
    } catch (_) {
      // The OCR name and editable provider fields remain available offline.
    }

    if (!mounted ||
        exactMatch == null ||
        phoneDigits(pharmacyPhoneController.text) != expectedDigits) {
      return;
    }

    setState(() {
      if (pharmacyNameController.text.trim().isEmpty) {
        pharmacyNameController.text = exactMatch!.name;
      }

      if (pharmacyAddressController.text.trim().isEmpty) {
        pharmacyAddressController.text = exactMatch!.address;
      }
    });
  }

  int scorePhoneCandidate(String lower) {
    int score = 0;

    if (lower.contains("phone")) {
      score += 8;
    }

    if (lower.contains("tel")) {
      score += 8;
    }

    if (lower.contains("pharmacy")) {
      score += 6;
    }

    if (lower.contains("clinic")) {
      score += 5;
    }

    if (lower.contains("call")) {
      score += 4;
    }

    if (lower.contains("fax")) {
      score -= 12;
    }

    if (lower.contains("ndc")) {
      score -= 10;
    }

    if (lower.contains("rx")) {
      score -= 4;
    }

    if (lower.contains("qty") || lower.contains("quantity")) {
      score -= 8;
    }

    if (lower.contains("patient")) {
      score -= 4;
    }

    return score;
  }

  String formatPhoneNumber(String value) {
    String digits = value.replaceAll(RegExp(r'[^0-9]'), "");

    if (digits.length == 11 && digits.startsWith("1")) {
      digits = digits.substring(1);
    }

    if (digits.length != 10) {
      return "";
    }

    return "(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}";
  }

  String extractDosageFromLines(List<String> lines) {
    final dosageRegExp = RegExp(
      r'\b\d+(\.\d+)?\s*(mg|mcg|g|gram|grams|ml|mL|units|unit|iu|IU|%)\b',
      caseSensitive: false,
    );

    for (final line in lines.where(
      (line) => !isInstructionLine(line.toLowerCase()),
    )) {
      final match = dosageRegExp.firstMatch(line);

      if (match != null) {
        return normalizeDosage(match.group(0) ?? "");
      }
    }

    final noSpaceDosageRegExp = RegExp(
      r'\b\d+(\.\d+)?(mg|mcg|ml|iu)\b',
      caseSensitive: false,
    );

    for (final line in lines.where(
      (line) => !isInstructionLine(line.toLowerCase()),
    )) {
      final match = noSpaceDosageRegExp.firstMatch(line);

      if (match != null) {
        final value = match.group(0) ?? "";

        return value
            .replaceAllMapped(
              RegExp(r'(\d+)([a-zA-Z]+)'),
              (match) => "${match.group(1)} ${match.group(2)}",
            )
            .toUpperCase();
      }
    }

    return "";
  }

  String normalizeDosage(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), " ");
  }

  String extractQuantity(List<String> lines) {
    final labeledQuantity = extractLabelQuantity(lines);

    if (labeledQuantity.isNotEmpty) {
      return labeledQuantity;
    }

    for (final line in lines) {
      final lower = line.toLowerCase();

      final adultSuppMatch = RegExp(
        r'\b(\d{1,4})\s*adult\s*suppositor(?:y|ies)\b',
        caseSensitive: false,
      ).firstMatch(line);

      if (adultSuppMatch != null) {
        return adultSuppMatch.group(1) ?? "";
      }

      final packageSuppMatch = RegExp(
        r'\b(\d{1,4})\s*suppositor(?:y|ies)\b',
        caseSensitive: false,
      ).firstMatch(line);

      if (packageSuppMatch != null && !isInstructionLine(lower)) {
        return packageSuppMatch.group(1) ?? "";
      }

      final packageMatch = RegExp(
        r'\b(\d{1,4})\s*(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|patch|patches|vial|vials|packet|packets|adult)\b',
        caseSensitive: false,
      ).firstMatch(line);

      if (packageMatch != null && !isInstructionLine(lower)) {
        return packageMatch.group(1) ?? "";
      }
    }

    return "";
  }

  bool isInstructionLine(String lower) {
    return instructionKeywordIndex(lower) >= 0 ||
        hasScheduleAbbreviation(lower) ||
        RegExp(
          r'\bq\s*\.?\s*\d{1,2}\s*\.?\s*(h|hr|hrs|hour|hours)\b',
          caseSensitive: false,
        ).hasMatch(lower) ||
        RegExp(
          r'\b\d{1,2}\s*(h|giờ|gio)\s*/?\s*(lần|lan)\b',
          caseSensitive: false,
        ).hasMatch(lower) ||
        RegExp(
          r'\b[1-6]\s*(x|times?|lần|lan)\s*(daily|a day|per day|mỗi ngày|moi ngay|ngày|ngay)\b',
          caseSensitive: false,
        ).hasMatch(lower);
  }

  bool hasScheduleAbbreviation(String value) {
    return RegExp(
      r'(^|[^a-z])(b\s*\.?\s*i\s*\.?\s*d|b\s*\.?\s*d|t\s*\.?\s*i\s*\.?\s*d|t\s*\.?\s*d\s*\.?\s*s|q\s*\.?\s*i\s*\.?\s*d|q\s*\.?\s*d|q\s*\.?\s*h\s*\.?\s*s|q\s*\.?\s*a\s*\.?\s*m|q\s*\.?\s*p\s*\.?\s*m|a\s*\.?\s*c|p\s*\.?\s*c)([^a-z]|$)',
      caseSensitive: false,
    ).hasMatch(value);
  }

  bool shouldIgnoreForMedicationName(String line) {
    final lower = line.toLowerCase();
    final cleaned = cleanMedicationName(line).toLowerCase();

    if (cleaned.length < 3) {
      return true;
    }

    if (isInstructionLine(lower)) {
      return true;
    }

    if (lower.contains("photo") ||
        lower.contains("professional") ||
        lower.contains("pharmacy") ||
        lower.contains("pharm") ||
        lower.contains("clinic") ||
        lower.contains("medical") ||
        lower.contains("rising") ||
        lower.contains("fairview") ||
        lower.contains("rx") ||
        lower.contains("ndc") ||
        lower.contains("patient") ||
        lower.contains("doctor") ||
        lower.contains("prescriber") ||
        lower.contains("date") ||
        lower.contains("refill") ||
        lower.contains("phone") ||
        lower.contains("tel") ||
        lower.contains("warning") ||
        lower.contains("caution") ||
        lower.contains("take") ||
        RegExp(
          r'\b(every|each|hourly)\b',
          caseSensitive: false,
        ).hasMatch(lower) ||
        RegExp(
          r'\bq\s*\d{1,2}\s*(h|hr|hrs|hour|hours)\b',
          caseSensitive: false,
        ).hasMatch(lower) ||
        lower.contains("directions") ||
        lower.contains("generic for") ||
        lower.contains("remaining") ||
        lower.contains("qty") ||
        lower.contains("quantity") ||
        lower.contains("use before") ||
        lower.contains("discard") ||
        lower.contains("label") ||
        lower.contains("for rectal use") ||
        lower.contains("rectal use only") ||
        lower.contains("adult suppositories") ||
        lower.contains("adult suppository") ||
        lower.contains("đặt") ||
        lower.contains("dat") ||
        lower.contains("vào") ||
        lower.contains("vao") ||
        lower.contains("bổ sung") ||
        lower.contains("bo sung") ||
        lower.contains("bệnh") ||
        lower.contains("benh") ||
        lower.contains("trĩ") ||
        lower.contains("tri") ||
        lower.contains("ngày") ||
        lower.contains("ngay") ||
        lower.contains("nếu") ||
        lower.contains("neu") ||
        lower.contains("cần") ||
        lower.contains("can")) {
      return true;
    }

    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(cleaned);

    if (!hasLetter) {
      return true;
    }

    return false;
  }

  int scoreMedicationNameCandidate(String value) {
    final lower = value.toLowerCase();
    int score = 0;

    if (value.length >= 5) {
      score += 2;
    }

    if (value == value.toUpperCase()) {
      score += 2;
    }

    final drugHints = [
      "docusate",
      "softener",
      "hydrocortisone",
      "hydrocortison",
      "acetate",
      "statin",
      "vastatin",
      "cillin",
      "cycline",
      "prazole",
      "sartan",
      "dipine",
      "olol",
      "formin",
      "mycin",
      "zole",
      "vir",
      "pril",
      "xetine",
      "zepam",
    ];

    for (final hint in drugHints) {
      if (lower.contains(hint)) {
        score += 10;
        break;
      }
    }

    if (RegExp(
      r'\b(hcl|er|xr|sr|dr)\b',
      caseSensitive: false,
    ).hasMatch(value)) {
      score += 4;
    }

    final wordCount = value.split(" ").where((word) => word.isNotEmpty).length;

    if (wordCount >= 4) {
      score -= 5;
    }

    if (RegExp(r'\d').hasMatch(value)) {
      score -= 3;
    }

    if (lower.contains("duy") ||
        lower.contains("truong") ||
        lower.contains("anh") ||
        lower.contains("nguyen") ||
        lower.contains("tran") ||
        lower.contains(" le ")) {
      score -= 8;
    }

    return score;
  }

  int scoreMedicationNamePosition(List<String> lines, int index) {
    final strengthPattern = RegExp(
      r'\b\d+(?:\.\d+)?\s*(mg|mcg|g|gram|grams|ml|units?|iu|%)\b',
      caseSensitive: false,
    );

    if (strengthPattern.hasMatch(lines[index])) {
      return 12;
    }

    for (int distance = 1; distance <= 2; distance++) {
      final previousIndex = index - distance;
      final nextIndex = index + distance;

      if (previousIndex >= 0 &&
          strengthPattern.hasMatch(lines[previousIndex]) &&
          !isInstructionLine(lines[previousIndex].toLowerCase())) {
        return distance == 1 ? 8 : 5;
      }

      if (nextIndex < lines.length &&
          strengthPattern.hasMatch(lines[nextIndex]) &&
          !isInstructionLine(lines[nextIndex].toLowerCase())) {
        return distance == 1 ? 8 : 5;
      }
    }

    return 0;
  }

  String cleanMedicationName(String value) {
    String cleaned = value.trim();

    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9à-ỹÀ-Ỹ\s\-]'), " ");
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), " ").trim();
    cleaned = cleaned.replaceFirst(
      RegExp(
        r'\s+\d+(?:\.\d+)?\s*(mg|mcg|g|gram|grams|ml|units?|iu|%)\b.*$',
        caseSensitive: false,
      ),
      "",
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), " ").trim();

    if (cleaned.length > 50) {
      cleaned = cleaned.substring(0, 50).trim();
    }

    return RxNormService.correctLikelyOcrMedicationName(cleaned);
  }

  String findDosageNearLine(List<String> lines, int index) {
    final dosageRegExp = RegExp(
      r'\b\d+(\.\d+)?\s*(mg|mcg|g|gram|grams|ml|mL|units|unit|iu|IU|%)\b',
      caseSensitive: false,
    );

    final sameLineMatch = dosageRegExp.firstMatch(lines[index]);

    if (sameLineMatch != null) {
      return normalizeDosage(sameLineMatch.group(0) ?? "");
    }

    for (int distance = 1; distance <= 5; distance++) {
      final candidateIndexes = [index - distance, index + distance];

      for (final candidateIndex in candidateIndexes) {
        if (candidateIndex < 0 || candidateIndex >= lines.length) {
          continue;
        }

        if (isInstructionLine(lines[candidateIndex].toLowerCase())) {
          continue;
        }

        final match = dosageRegExp.firstMatch(lines[candidateIndex]);

        if (match != null) {
          return normalizeDosage(match.group(0) ?? "");
        }
      }
    }

    return "";
  }

  String extractStrongInstructionFromText(String text) {
    String lower = TimeHelper.normalizeInstruction(text);

    lower = lower.replaceAll("\n", " ");
    lower = lower.replaceAll(RegExp(r'\s+'), " ");

    final compact = normalizeTextForMatching(lower);

    final mergedEnglishAmbiguousDailyMealMatch = RegExp(
      r'(take|give|use|swallow)?(\d+|one|two|three|four|five|six)(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|pill|pills|drop|drops|puff|puffs|patch|patches|suppository|suppositories)(?:bymouth)?(eachday|everyday|onceaday|onceperday|daily)(after(?:eat|eating|food|ameal|meal)?orbefore(?:eat|eating|food|ameal|meal)?|before(?:eat|eating|food|ameal|meal)?orafter(?:eat|eating|food|ameal|meal)?)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedEnglishAmbiguousDailyMealMatch != null) {
      final amount = mergedEnglishAmbiguousDailyMealMatch.group(2) ?? "1";
      final unit = mergedEnglishAmbiguousDailyMealMatch.group(3) ?? "dose";

      return "Take $amount $unit once daily after or before eating.";
    }

    final mergedEnglishDailyMealMatch = RegExp(
      r'(take|give|use|swallow)?(\d+|one|two|three|four|five|six)(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|pill|pills|drop|drops|puff|puffs|patch|patches|suppository|suppositories)(?:bymouth)?(eachday|everyday|onceaday|onceperday|daily)(after|before)(eat|eating|food|ameal|meal|meals)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedEnglishDailyMealMatch != null) {
      final amount = mergedEnglishDailyMealMatch.group(2) ?? "1";
      final unit = mergedEnglishDailyMealMatch.group(3) ?? "dose";
      final mealSide = mergedEnglishDailyMealMatch.group(5) == "before"
          ? "before"
          : "after";

      return "Take $amount $unit once daily $mealSide eating.";
    }

    final mergedVietnameseAmbiguousDailyMealMatch = RegExp(
      r'(uong|dung)?(\d+|mot|hai|ba|bon|nam|sau)(vien|giot|nhat|lieu)(moingay|ngaymotlan|motlanmoingay|hangngay)(sau(?:an|buaan)?hoactruoc(?:an|buaan)?|truoc(?:an|buaan)?hoacsau(?:an|buaan)?)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedVietnameseAmbiguousDailyMealMatch != null) {
      final amount = mergedVietnameseAmbiguousDailyMealMatch.group(2) ?? "1";
      final unit = mergedVietnameseAmbiguousDailyMealMatch.group(3) ?? "liều";

      return "Uống $amount $unit mỗi ngày sau hoặc trước ăn.";
    }

    final mergedVietnameseDailyMealMatch = RegExp(
      r'(uong|dung)?(\d+|mot|hai|ba|bon|nam|sau)(vien|giot|nhat|lieu)(moingay|ngaymotlan|motlanmoingay|hangngay)(sau|truoc)(an|buaan)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedVietnameseDailyMealMatch != null) {
      final amount = mergedVietnameseDailyMealMatch.group(2) ?? "1";
      final unit = mergedVietnameseDailyMealMatch.group(3) ?? "liều";
      final mealSide = mergedVietnameseDailyMealMatch.group(5) == "truoc"
          ? "trước"
          : "sau";

      return "Uống $amount $unit mỗi ngày $mealSide ăn.";
    }

    final mergedEnglishIntervalMatch = RegExp(
      r'(take|give|use|swallow|inhale|instill|insert|apply)(\d+|one|two|three|four|five|six)(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|pill|pills|drop|drops|puff|puffs|patch|patches|suppository|suppositories)(every|each)(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(hour|hours|hr|hrs|h)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedEnglishIntervalMatch != null) {
      final action = mergedEnglishIntervalMatch.group(1) ?? "Take";
      final amount = mergedEnglishIntervalMatch.group(2) ?? "1";
      final unit = mergedEnglishIntervalMatch.group(3) ?? "dose";
      final interval = mergedEnglishIntervalMatch.group(5) ?? "";

      return "${capitalizeFirst(action)} $amount $unit every $interval hours.";
    }

    final mergedEnglishQIntervalMatch = RegExp(
      r'(take|give|use|swallow|inhale|instill|insert|apply)(\d+|one|two|three|four|five|six)(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|pill|pills|drop|drops|puff|puffs|patch|patches|suppository|suppositories)q(\d{1,2})(h|hr|hrs)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedEnglishQIntervalMatch != null) {
      final action = mergedEnglishQIntervalMatch.group(1) ?? "Take";
      final amount = mergedEnglishQIntervalMatch.group(2) ?? "1";
      final unit = mergedEnglishQIntervalMatch.group(3) ?? "dose";
      final interval = mergedEnglishQIntervalMatch.group(4) ?? "";

      return "${capitalizeFirst(action)} $amount $unit every $interval hours.";
    }

    final mergedVietnameseIntervalMatch = RegExp(
      r'(uong|dung|dat|nho|xit|boi|tiem)(\d+|mot|hai|ba|bon|nam|sau)(vien|giot|nhat|lieu)(moi|cu|cach)(\d{1,2})(gio|tieng|h)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedVietnameseIntervalMatch != null) {
      final action = formatVietnameseAction(
        mergedVietnameseIntervalMatch.group(1) ?? "uong",
      );
      final amount = mergedVietnameseIntervalMatch.group(2) ?? "1";
      final unit = mergedVietnameseIntervalMatch.group(3) ?? "liều";
      final interval = mergedVietnameseIntervalMatch.group(5) ?? "";

      return "$action $amount $unit mỗi $interval giờ.";
    }

    final mergedEnglishDailyMatch = RegExp(
      r'(take|give|use|swallow|inhale|instill|insert|apply)(\d+|one|two|three|four|five|six)(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|pill|pills|drop|drops|puff|puffs|patch|patches|suppository|suppositories)(once|twice|threetimes|fourtimes|fivetimes|sixtimes|[1-6]times)(daily|aday|perday)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedEnglishDailyMatch != null) {
      final action = mergedEnglishDailyMatch.group(1) ?? "Take";
      final amount = mergedEnglishDailyMatch.group(2) ?? "1";
      final unit = mergedEnglishDailyMatch.group(3) ?? "dose";
      final frequency = formatMergedDailyFrequency(
        mergedEnglishDailyMatch.group(4) ?? "once",
      );

      return "${capitalizeFirst(action)} $amount $unit $frequency daily.";
    }

    final mergedEnglishAbbreviationMatch = RegExp(
      r'(take|give|use|swallow|inhale|instill|insert|apply)(\d+|one|two|three|four|five|six)(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|pill|pills|drop|drops|puff|puffs|patch|patches|suppository|suppositories)(bid|bd|tid|tds|qid|qd|qhs|qam|qpm|ac|pc)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedEnglishAbbreviationMatch != null) {
      final action = mergedEnglishAbbreviationMatch.group(1) ?? "Take";
      final amount = mergedEnglishAbbreviationMatch.group(2) ?? "1";
      final unit = mergedEnglishAbbreviationMatch.group(3) ?? "dose";
      final abbreviation = mergedEnglishAbbreviationMatch.group(4) ?? "qd";

      return "${capitalizeFirst(action)} $amount $unit ${formatMergedAbbreviation(abbreviation)}.";
    }

    final mergedVietnameseDailyMatch = RegExp(
      r'(uong|dung|dat|nho|xit|boi|tiem)(\d+|mot|hai|ba|bon|nam|sau)(vien|giot|nhat|lieu)(moingay|ngay)([1-6])(lan)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedVietnameseDailyMatch != null) {
      final action = formatVietnameseAction(
        mergedVietnameseDailyMatch.group(1) ?? "uong",
      );
      final amount = mergedVietnameseDailyMatch.group(2) ?? "1";
      final unit = mergedVietnameseDailyMatch.group(3) ?? "liều";
      final frequency = mergedVietnameseDailyMatch.group(5) ?? "1";

      return "$action $amount $unit $frequency lần mỗi ngày.";
    }

    final mergedVietnameseReverseDailyMatch = RegExp(
      r'(uong|dung|dat|nho|xit|boi|tiem)(\d+|mot|hai|ba|bon|nam|sau)(vien|giot|nhat|lieu)([1-6])(lan)(moingay|ngay)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (mergedVietnameseReverseDailyMatch != null) {
      final action = formatVietnameseAction(
        mergedVietnameseReverseDailyMatch.group(1) ?? "uong",
      );
      final amount = mergedVietnameseReverseDailyMatch.group(2) ?? "1";
      final unit = mergedVietnameseReverseDailyMatch.group(3) ?? "liều";
      final frequency = mergedVietnameseReverseDailyMatch.group(4) ?? "1";

      return "$action $amount $unit $frequency lần mỗi ngày.";
    }

    if (compact.contains("takeonetableteverynight") ||
        compact.contains("takeonetableteverynightat") ||
        compact.contains("take1tableteverynight") ||
        compact.contains("takeonetableteverybedtime") ||
        compact.contains("take1tableteverybedtime")) {
      return "Take one tablet every night.";
    }

    final englishNightMatch = RegExp(
      r'take\s*(one|1)\s*tablet\s*(by mouth\s*)?(every|each)?\s*(night|bedtime)',
      caseSensitive: false,
    ).firstMatch(lower);

    if (englishNightMatch != null) {
      return "Take one tablet every night.";
    }

    if ((compact.contains("uong1vien") || compact.contains("uống1viên")) &&
        (compact.contains("moitoi") ||
            compact.contains("mỗitối") ||
            compact.contains("moidem") ||
            compact.contains("mỗidem") ||
            compact.contains("ngutri") ||
            compact.contains("ngủtrị"))) {
      return "Uống 1 viên mỗi tối.";
    }

    final vietnameseNightMatch = RegExp(
      r'(uống|uong)\s*1\s*(viên|vien).*?(mỗi|moi|ngủ|ngu|tối|toi)',
      caseSensitive: false,
    ).firstMatch(lower);

    if (vietnameseNightMatch != null) {
      return "Uống 1 viên mỗi tối.";
    }

    return "";
  }

  String capitalizeFirst(String value) {
    final cleanValue = value.trim();

    if (cleanValue.isEmpty) {
      return cleanValue;
    }

    return "${cleanValue[0].toUpperCase()}${cleanValue.substring(1)}";
  }

  String formatMergedDailyFrequency(String value) {
    final cleanValue = value.toLowerCase().trim();

    if (cleanValue == "threetimes") {
      return "three times";
    }

    if (cleanValue == "fourtimes") {
      return "four times";
    }

    if (cleanValue == "fivetimes") {
      return "five times";
    }

    if (cleanValue == "sixtimes") {
      return "six times";
    }

    return cleanValue;
  }

  String formatVietnameseAction(String value) {
    switch (value.toLowerCase().trim()) {
      case "dung":
        return "Dùng";
      case "dat":
        return "Đặt";
      case "nho":
        return "Nhỏ";
      case "xit":
        return "Xịt";
      case "boi":
        return "Bôi";
      case "tiem":
        return "Tiêm";
      default:
        return "Uống";
    }
  }

  String formatMergedAbbreviation(String value) {
    switch (value.toLowerCase().trim()) {
      case "bid":
      case "bd":
        return "twice daily";
      case "tid":
      case "tds":
        return "three times daily";
      case "qid":
        return "four times daily";
      case "qhs":
        return "at bedtime";
      case "qam":
        return "every morning";
      case "qpm":
        return "every evening";
      case "ac":
      case "pc":
        return "with meals";
      default:
        return "once daily";
    }
  }

  String extractBestInstructions(List<String> lines) {
    final instructionCandidates = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final keywordIndex = instructionKeywordIndex(line);

      if (keywordIndex >= 0) {
        final parts = <String>[];

        final beforeKeyword = line.substring(0, keywordIndex).trim();
        final hasDoseBeforeKeyword = isDoseInstructionFragment(beforeKeyword);

        if (!hasDoseBeforeKeyword &&
            startsWithIntervalInstruction(line.substring(keywordIndex)) &&
            i > 0) {
          final previousLine = lines[i - 1].trim();

          if (isDoseInstructionFragment(previousLine) &&
              !shouldIgnoreInstructionContinuation(previousLine)) {
            parts.add(previousLine);
          }
        }

        final firstInstructionPart = line
            .substring(hasDoseBeforeKeyword ? 0 : keywordIndex)
            .trim();

        if (firstInstructionPart.isNotEmpty) {
          parts.add(firstInstructionPart);
        }

        for (int j = i + 1; j < lines.length && j <= i + 5; j++) {
          final currentLine = lines[j].trim();
          final currentLower = currentLine.toLowerCase();

          if (isInstructionStopLine(currentLower)) {
            break;
          }

          if (shouldIgnoreInstructionContinuation(currentLine)) {
            continue;
          }

          if (currentLine.isNotEmpty) {
            parts.add(currentLine);
          }
        }

        final candidate = cleanInstructionText(parts.join(" "));

        if (candidate.isNotEmpty) {
          instructionCandidates.add(candidate);
        }
      }
    }

    if (instructionCandidates.isEmpty) {
      return "";
    }

    instructionCandidates.sort(
      (a, b) =>
          scoreInstructionCandidate(b).compareTo(scoreInstructionCandidate(a)),
    );

    return instructionCandidates.first;
  }

  bool isDoseInstructionFragment(String value) {
    final interpretedValue = TimeHelper.normalizeInstruction(value);

    return RegExp(
      r'\b(\d{1,2}|one|two|three|four|five|six|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau)\s*(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|pill|pills|suppository|suppositories|drop|drops|puff|puffs|patch|patches|spray|sprays|teaspoon|teaspoons|tablespoon|tablespoons|ml|unit|units|viên|vien|giọt|giot|nhát|nhat|muỗng|muong)\b',
      caseSensitive: false,
    ).hasMatch(interpretedValue);
  }

  bool startsWithIntervalInstruction(String value) {
    final lower = TimeHelper.normalizeInstruction(value);

    return lower.startsWith("every") ||
        lower.startsWith("each") ||
        lower.startsWith("hourly") ||
        lower.startsWith("once") ||
        lower.startsWith("twice") ||
        lower.startsWith("daily") ||
        lower.startsWith("morning") ||
        lower.startsWith("afternoon") ||
        lower.startsWith("evening") ||
        lower.startsWith("night") ||
        lower.startsWith("bedtime") ||
        lower.startsWith("with food") ||
        lower.startsWith("with meals") ||
        lower.startsWith("with a meal") ||
        lower.startsWith("after eat") ||
        lower.startsWith("after eating") ||
        lower.startsWith("after food") ||
        lower.startsWith("after meal") ||
        lower.startsWith("before eat") ||
        lower.startsWith("before eating") ||
        lower.startsWith("before food") ||
        lower.startsWith("before meal") ||
        lower.startsWith("empty stomach") ||
        lower.startsWith("as needed") ||
        lower.startsWith("mỗi") ||
        lower.startsWith("moi") ||
        lower.startsWith("cứ") ||
        lower.startsWith("cu ") ||
        lower.startsWith("cách") ||
        lower.startsWith("cach") ||
        lower.startsWith("ngày") ||
        lower.startsWith("ngay") ||
        lower.startsWith("sáng") ||
        lower.startsWith("sang") ||
        lower.startsWith("trưa") ||
        lower.startsWith("trua") ||
        lower.startsWith("chiều") ||
        lower.startsWith("chieu") ||
        lower.startsWith("tối") ||
        lower.startsWith("toi") ||
        hasScheduleAbbreviation(lower) ||
        RegExp(
          r'^q\s*\.?\s*\d{1,2}\s*\.?\s*(h|hr|hrs|hour|hours)',
          caseSensitive: false,
        ).hasMatch(lower);
  }

  int instructionKeywordIndex(String line) {
    final lower = line.toLowerCase();

    final keywords = [
      "directions",
      "direction",
      "instructions",
      "instruction",
      "description",
      "sig",
      "hướng dẫn",
      "huong dan",
      "mô tả",
      "mo ta",
      "cách dùng",
      "cach dung",
      "liều dùng",
      "lieu dung",
      "take",
      "give",
      "administer",
      "swallow",
      "inhale",
      "instill",
      "inject",
      "uống",
      "uong",
      "dùng",
      "dung",
      "use",
      "apply",
      "inject",
      "inhale",
      "chew",
      "dissolve",
      "insert",
      "đặt",
      "dat",
      "nhỏ",
      "nho",
      "xịt",
      "xit",
      "bôi",
      "boi",
      "tiêm",
      "tiem",
      "by mouth",
      "every",
      "each",
      "hourly",
      "daily",
      "once",
      "twice",
      "three times",
      "four times",
      "times a day",
      "times per day",
      "morning",
      "afternoon",
      "evening",
      "night",
      "bedtime",
      "breakfast",
      "lunch",
      "dinner",
      "with food",
      "with meals",
      "with a meal",
      "after eat",
      "after eating",
      "after food",
      "after meal",
      "before eat",
      "before eating",
      "before food",
      "before meal",
      "empty stomach",
      "as needed",
      "prn",
      "rectally",
      "rectal",
      "mỗi",
      "moi",
      "cứ",
      "cu",
      "cách",
      "cach",
      "ngày",
      "ngay",
      "lần",
      "lan",
      "sáng",
      "sang",
      "trưa",
      "trua",
      "chiều",
      "chieu",
      "tối",
      "toi",
      "khi cần",
      "khi can",
      "sau ăn",
      "sau an",
      "trước ăn",
      "truoc an",
      "sau bữa ăn",
      "sau bua an",
      "trước bữa ăn",
      "truoc bua an",
      "bụng đói",
      "bung doi",
    ];

    int bestIndex = -1;

    for (final keyword in keywords) {
      final match = RegExp(
        r'(^|[^a-z0-9à-ỹ])' + RegExp.escape(keyword) + r'([^a-z0-9à-ỹ]|$)',
        caseSensitive: false,
      ).firstMatch(lower);

      if (match == null) {
        continue;
      }

      final prefixLength = match.group(1)?.length ?? 0;
      final index = match.start + prefixLength;

      if (index >= 0 && (bestIndex == -1 || index < bestIndex)) {
        bestIndex = index;
      }
    }

    const correctedTriggerTerms = {
      "directions",
      "direction",
      "instructions",
      "instruction",
      "description",
      "take",
      "give",
      "administer",
      "swallow",
      "inhale",
      "instill",
      "inject",
      "use",
      "apply",
      "chew",
      "dissolve",
      "insert",
      "every",
      "each",
      "daily",
      "once",
      "twice",
      "morning",
      "afternoon",
      "evening",
      "night",
      "bedtime",
      "breakfast",
      "lunch",
      "dinner",
      "before",
      "after",
      "prn",
      "uong",
      "dung",
      "moi",
      "ngay",
      "lan",
      "truoc",
      "sau",
      "sang",
      "toi",
    };

    for (final wordMatch in RegExp(r'[a-z0-9à-ỹ]+').allMatches(lower)) {
      final originalTerm = wordMatch.group(0) ?? "";
      final correctedTerm = TimeHelper.correctInstructionTerm(originalTerm);
      final correctedWords = correctedTerm.split(" ");

      if (correctedTerm != originalTerm &&
          correctedWords.any(correctedTriggerTerms.contains) &&
          (bestIndex == -1 || wordMatch.start < bestIndex)) {
        bestIndex = wordMatch.start;
      }
    }

    final qIntervalMatch = RegExp(
      r'\bq\s*\.?\s*\d{1,2}\s*\.?\s*(h|hr|hrs|hour|hours)\b',
      caseSensitive: false,
    ).firstMatch(lower);

    if (qIntervalMatch != null &&
        (bestIndex == -1 || qIntervalMatch.start < bestIndex)) {
      bestIndex = qIntervalMatch.start;
    }

    final abbreviationMatch = RegExp(
      r'(^|[^a-z])(b\s*\.?\s*i\s*\.?\s*d|b\s*\.?\s*d|t\s*\.?\s*i\s*\.?\s*d|t\s*\.?\s*d\s*\.?\s*s|q\s*\.?\s*i\s*\.?\s*d|q\s*\.?\s*d|q\s*\.?\s*h\s*\.?\s*s|q\s*\.?\s*a\s*\.?\s*m|q\s*\.?\s*p\s*\.?\s*m|a\s*\.?\s*c|p\s*\.?\s*c)([^a-z]|$)',
      caseSensitive: false,
    ).firstMatch(lower);

    if (abbreviationMatch != null &&
        (bestIndex == -1 || abbreviationMatch.start < bestIndex)) {
      bestIndex = abbreviationMatch.start;
    }

    return bestIndex;
  }

  bool shouldIgnoreInstructionContinuation(String line) {
    final lower = line.toLowerCase();

    if (isAdministrativePrescriptionLine(line) ||
        lower.contains("photo") ||
        lower.contains("professional") ||
        lower.contains("pharmacy") ||
        lower.contains("clinic") ||
        lower.contains("fairview") ||
        lower.contains("rx") ||
        lower.contains("ndc") ||
        lower.contains("patient") ||
        lower.contains("doctor") ||
        lower.contains("prescriber") ||
        lower.contains("generic for") ||
        lower.contains("phone") ||
        lower.contains("tel") ||
        lower.contains("cc#") ||
        RegExp(r'\d{6,}').hasMatch(lower)) {
      return true;
    }

    return false;
  }

  bool isInstructionStopLine(String lower) {
    return isAdministrativePrescriptionLine(lower) ||
        lower.contains("photo") ||
        lower.contains("rx") ||
        lower.contains("ndc") ||
        lower.contains("doctor") ||
        lower.contains("prescriber") ||
        lower.contains("pharmacy") ||
        lower.contains("clinic") ||
        lower.contains("phone") ||
        lower.contains("tel") ||
        lower.contains("date") ||
        lower.contains("cc#") ||
        RegExp(r'\d{6,}').hasMatch(lower);
  }

  int scoreInstructionCandidate(String value) {
    final lower = TimeHelper.normalizeInstruction(value);
    int score = 0;

    if (lower.contains("take") ||
        lower.contains("give") ||
        lower.contains("administer") ||
        lower.contains("swallow") ||
        lower.contains("inhale") ||
        lower.contains("instill") ||
        lower.contains("inject") ||
        lower.contains("use") ||
        lower.contains("apply") ||
        lower.contains("uống") ||
        lower.contains("uong") ||
        lower.contains("dùng") ||
        lower.contains("dung") ||
        lower.contains("insert") ||
        lower.contains("đặt") ||
        lower.contains("dat") ||
        lower.contains("rectally") ||
        lower.contains("rectal")) {
      score += 10;
    }

    if (lower.contains("tablet") ||
        lower.contains("capsule") ||
        lower.contains("supp") ||
        lower.contains("suppository") ||
        lower.contains("viên") ||
        lower.contains("vien")) {
      score += 6;
    }

    if (lower.contains("daily") ||
        lower.contains("every") ||
        lower.contains("each") ||
        lower.contains("hourly") ||
        lower.contains("twice") ||
        lower.contains("times a day") ||
        lower.contains("times per day") ||
        lower.contains("morning") ||
        lower.contains("afternoon") ||
        lower.contains("evening") ||
        lower.contains("2 lần") ||
        lower.contains("2 lan") ||
        lower.contains("night") ||
        lower.contains("bedtime") ||
        lower.contains("after eat") ||
        lower.contains("after eating") ||
        lower.contains("after food") ||
        lower.contains("after meal") ||
        lower.contains("before eat") ||
        lower.contains("before eating") ||
        lower.contains("before food") ||
        lower.contains("before meal") ||
        lower.contains("empty stomach") ||
        lower.contains("mỗi") ||
        lower.contains("moi") ||
        lower.contains("ngủ") ||
        lower.contains("ngu") ||
        lower.contains("tối") ||
        lower.contains("toi") ||
        hasScheduleAbbreviation(lower) ||
        RegExp(
          r'\bq\s*\.?\s*\d{1,2}\s*\.?\s*(h|hr|hrs|hour|hours)\b',
          caseSensitive: false,
        ).hasMatch(lower)) {
      score += 6;
    }

    if (value.length > 20) {
      score += 4;
    }

    if (value.length > 140) {
      score -= 8;
    }

    if (lower.contains("patient") ||
        lower.contains("pharmacy") ||
        lower.contains("clinic") ||
        lower.contains("use the label") ||
        lower.contains("project") ||
        lower.contains("reminder") ||
        lower.contains("example") ||
        lower.contains("generic for") ||
        lower.contains("rx") ||
        lower.contains("ndc") ||
        lower.contains("remaining") ||
        lower.contains("qty") ||
        lower.contains("phone") ||
        lower.contains("tel") ||
        lower.contains("cc#") ||
        RegExp(r'\d{6,}').hasMatch(lower)) {
      score -= 15;
    }

    return score;
  }

  String cleanInstructionText(String value) {
    String cleaned = stripAdministrativePrescriptionText(value);

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), " ");

    cleaned = cleaned.replaceAll(RegExp(r'CC#.*', caseSensitive: false), "");
    cleaned = cleaned.replaceAll(RegExp(r'\d{6,}'), "");
    cleaned = cleaned.replaceAll(
      RegExp(r'Photo\s+\d+', caseSensitive: false),
      "",
    );

    cleaned = cleaned.replaceFirst(
      RegExp(
        r'^(directions?|direcitons|directons|directon|instructions?|instrutions|instuctions|instrction|description|descrption|sig|hướng dẫn|huong dan|mô tả|mo ta|cách dùng|cach dung|liều dùng|lieu dung)\s*[:\-]?\s*',
        caseSensitive: false,
      ),
      "",
    );

    cleaned = cleaned.replaceAll(
      RegExp(r'TAKEONE', caseSensitive: false),
      "TAKE ONE",
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'TABLETEV', caseSensitive: false),
      "TABLET EV",
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'TABLET EVERYNIGHT', caseSensitive: false),
      "TABLET EVERY NIGHT",
    );

    final lowerCleaned = cleaned.toLowerCase();
    final actionWords = [
      "take",
      "give",
      "administer",
      "swallow",
      "inhale",
      "instill",
      "inject",
      "insert",
      "use",
      "apply",
      "chew",
      "dissolve",
      "rectal",
      "uống",
      "uong",
      "dùng",
      "dung",
      "đặt",
      "dat",
      "nhỏ",
      "nho",
      "xịt",
      "xit",
      "bôi",
      "boi",
      "tiêm",
      "tiem",
    ];

    final indexes = <int>[];

    for (final actionWord in actionWords) {
      final match = RegExp(
        r'(^|[^a-z0-9à-ỹ])' + RegExp.escape(actionWord) + r'([^a-z0-9à-ỹ]|$)',
        caseSensitive: false,
      ).firstMatch(lowerCleaned);

      if (match != null) {
        indexes.add(match.start + (match.group(1)?.length ?? 0));
      }
    }

    if (indexes.isNotEmpty) {
      indexes.sort();
      final firstActionIndex = indexes.first;
      final prefix = cleaned.substring(0, firstActionIndex).trim();

      if (prefix.isEmpty ||
          (instructionKeywordIndex(prefix) < 0 &&
              !startsWithIntervalInstruction(prefix))) {
        cleaned = cleaned.substring(firstActionIndex).trim();
      }
    }

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), " ").trim();

    if (cleaned.length > 320) {
      cleaned = cleaned.substring(0, 320).trim();
    }

    return cleaned;
  }

  String extractNotes(List<String> lines) {
    final noteParts = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();

      if (lower.contains("warning") ||
          lower.contains("caution") ||
          lower.contains("avoid") ||
          lower.contains("do not") ||
          lower.contains("with food") ||
          lower.contains("water") ||
          lower.contains("plenty") ||
          lower.contains("may cause") ||
          lower.contains("finish all") ||
          lower.contains("alcohol") ||
          lower.contains("drowsy") ||
          lower.contains("antacid") ||
          lower.contains("aluminum") ||
          lower.contains("magnesium") ||
          lower.contains("for rectal use only") ||
          lower.contains("rectal use only")) {
        noteParts.add(line);

        for (int j = i + 1; j < lines.length && j <= i + 2; j++) {
          final nextLine = lines[j].trim();
          final nextLower = nextLine.toLowerCase();

          if (isInstructionStopLine(nextLower)) {
            break;
          }

          if (shouldIgnoreInstructionContinuation(nextLine)) {
            continue;
          }

          if (nextLine.isNotEmpty) {
            noteParts.add(nextLine);
          }
        }
      }
    }

    String notes = noteParts.join(" ");
    notes = notes.replaceAll(RegExp(r'\s+'), " ").trim();

    if (notes.length > 320) {
      notes = notes.substring(0, 320).trim();
    }

    return notes;
  }

  Future<void> removeImage(int index) async {
    if (index < 0 || index >= selectedImages.length) {
      return;
    }

    setState(() {
      selectedImages.removeAt(index);
      clearExtractedTextOnly();
    });

    if (selectedImages.isNotEmpty) {
      await readTextFromAllImages();
    }
  }

  void clearAllImages() {
    setState(() {
      selectedImages.clear();
      clearExtractedTextOnly();
    });
  }

  String dateToString(DateTime date) {
    final year = date.year.toString().padLeft(4, "0");
    final month = date.month.toString().padLeft(2, "0");
    final day = date.day.toString().padLeft(2, "0");

    return "$year-$month-$day";
  }

  Future<void> goToMedicationDetails() async {
    final didSave = await Navigator.push<bool>(
      context,
      slowPageRoute(
        builder: (context) => MedicationDetailsPage(
          medication: Medication(
            name: nameController.text.trim(),
            dosage: dosageController.text.trim(),
            quantity: quantityController.text.trim(),
            remainingQuantity: quantityController.text.trim(),
            pharmacyName: pharmacyNameController.text.trim(),
            pharmacyAddress: pharmacyAddressController.text.trim(),
            pharmacyPhone: pharmacyPhoneController.text.trim(),
            instructions: instructionsController.text.trim(),
            notes: notesController.text.trim(),
            startDate: dateToString(DateTime.now()),
          ),
        ),
      ),
    );

    if (didSave == true && mounted) {
      if (widget.embeddedInHomeShell) {
        clearAllImages();
        await widget.onMedicationSaved?.call();
      } else {
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> goToManualMedicationDetails() async {
    final didSave = await Navigator.push<bool>(
      context,
      slowPageRoute(builder: (context) => const MedicationDetailsPage()),
    );

    if (didSave == true && mounted) {
      if (widget.embeddedInHomeShell) {
        clearAllImages();
        await widget.onMedicationSaved?.call();
      } else {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  void dispose() {
    medicationSearchDebounce?.cancel();
    medicationSuggestionDismissTimer?.cancel();
    medicationNameFocusNode.removeListener(handleMedicationNameFocusChanged);
    nameController.dispose();
    dosageController.dispose();
    quantityController.dispose();
    pharmacyNameController.dispose();
    pharmacyAddressController.dispose();
    pharmacyPhoneController.dispose();
    instructionsController.dispose();
    notesController.dispose();
    medicationNameFocusNode.dispose();
    dosageFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final hasImages = selectedImages.isNotEmpty;
    final hasScannedText = scannedText.trim().isNotEmpty;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: AppTheme.pagePadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTheme.formMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.embeddedInHomeShell) ...[
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.arrow_back_ios),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      AppLanguage.text("scanPrescription"),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E2A3A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      language == "en"
                          ? (Platform.isMacOS
                                ? "Choose one or more prescription-label photos. Apple Vision will read and combine the text on this Mac."
                                : "Take one or more photos of the prescription label. The app will combine the text.")
                          : (Platform.isMacOS
                                ? "Chọn một hoặc nhiều ảnh nhãn thuốc. Apple Vision sẽ đọc và ghép chữ trên máy Mac này."
                                : "Chụp một hoặc nhiều ảnh nhãn thuốc. Ứng dụng sẽ ghép chữ lại."),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF667085),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const ScanQualityTipCard(),
                    const SizedBox(height: 18),
                    ScanPreviewCard(
                      selectedImages: selectedImages,
                      onRemoveImage: removeImage,
                      onClearAll: clearAllImages,
                    ),
                    const SizedBox(height: 24),
                    if (!Platform.isMacOS) ...[
                      SmoothActionButton(
                        key: widget.cameraGuideTargetKey,
                        icon: Icons.camera_alt_rounded,
                        label: hasImages
                            ? (language == "en"
                                  ? "Add Another Photo"
                                  : "Thêm Ảnh Khác")
                            : AppLanguage.text("scanPrescription"),
                        onPressed: () {
                          unawaited(showCameraGuide());
                        },
                        isLoading: isOpeningCamera,
                      ),
                      const SizedBox(height: 14),
                    ],
                    SmoothActionButton(
                      key: widget.photoLibraryGuideTargetKey,
                      icon: Icons.photo_library_rounded,
                      label: hasImages
                          ? (language == "en"
                                ? "Add Photos from Library"
                                : "Thêm Ảnh Từ Thư Viện")
                          : (language == "en"
                                ? "Choose from Photo Library"
                                : "Chọn Từ Thư Viện Ảnh"),
                      outlined: !Platform.isMacOS,
                      onPressed: () {
                        unawaited(pickImageFromGallery());
                      },
                      isLoading: isOpeningGallery,
                    ),
                    if (hasImages) ...[
                      const SizedBox(height: 22),
                      ScanSuccessCard(imageCount: selectedImages.length),
                      const SizedBox(height: 18),
                      if (isReadingText)
                        ReadingTextCard(imageCount: selectedImages.length)
                      else
                        ConfirmScannedInfoCard(
                          imageCount: selectedImages.length,
                          hasScannedText: hasScannedText,
                          nameController: nameController,
                          dosageController: dosageController,
                          quantityController: quantityController,
                          pharmacyNameController: pharmacyNameController,
                          pharmacyAddressController: pharmacyAddressController,
                          pharmacyPhoneController: pharmacyPhoneController,
                          instructionsController: instructionsController,
                          notesController: notesController,
                          scannedText: scannedText,
                          showRawText: showRawText,
                          onToggleRawText: () {
                            setState(() {
                              showRawText = !showRawText;
                            });
                          },
                          onReadAgain: readTextFromAllImages,
                          medicationNameFocusNode: medicationNameFocusNode,
                          dosageFocusNode: dosageFocusNode,
                          medicationSuggestionsOpen: medicationSuggestionsOpen,
                          isSearchingRxNorm: isSearchingRxNorm,
                          medicationSuggestions: visibleMedicationSuggestions,
                          rxNormSearchMessage: rxNormSearchMessage,
                          scanEvidence: scanEvidence,
                          recognizedOcrLineCount: recognizedOcrLineCount,
                          lowConfidenceOcrLineCount: lowConfidenceOcrLineCount,
                          onDetailsChanged: () {
                            setState(() {});
                          },
                          onMedicationNameChanged: handleMedicationNameChanged,
                          onMedicationSuggestionInteractionStart: () {
                            medicationSuggestionDismissTimer?.cancel();
                          },
                          onSelectMedication: selectMedicationSuggestion,
                        ),
                      const SizedBox(height: 18),
                      SmoothActionButton(
                        icon: Icons.check_circle_rounded,
                        label: language == "en"
                            ? "Continue with Combined Details"
                            : "Tiếp Tục Với Thông Tin Đã Ghép",
                        onPressed: goToMedicationDetails,
                      ),
                    ],
                    const SizedBox(height: 18),
                    SmoothActionButton(
                      icon: Icons.medication_rounded,
                      label: language == "en"
                          ? "Enter Medication Manually"
                          : "Nhập Thuốc Thủ Công",
                      outlined: true,
                      onPressed: goToManualMedicationDetails,
                    ),
                    const SizedBox(height: 24),
                    const ScanSafetyNote(),
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

class PhoneCandidate {
  final String phone;
  final int score;

  const PhoneCandidate({required this.phone, required this.score});
}

class MedicationExtractedInfo {
  final String name;
  final String dosage;
  final String quantity;
  final String pharmacyName;
  final String pharmacyAddress;
  final String pharmacyPhone;
  final String instructions;
  final String notes;

  const MedicationExtractedInfo({
    required this.name,
    required this.dosage,
    required this.quantity,
    this.pharmacyName = "",
    this.pharmacyAddress = "",
    this.pharmacyPhone = "",
    required this.instructions,
    required this.notes,
  });
}

class OcrAccuracyCard extends StatelessWidget {
  final int recognizedLineCount;
  final int lowConfidenceLineCount;

  const OcrAccuracyCard({
    super.key,
    required this.recognizedLineCount,
    required this.lowConfidenceLineCount,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final hasUnclearLines = lowConfidenceLineCount > 0;
    final color = hasUnclearLines
        ? const Color(0xFFF59E0B)
        : const Color(0xFF2563EB);

    final title = language == "en"
        ? "Check the important details"
        : "Kiểm tra thông tin quan trọng";

    final message = hasUnclearLines
        ? (language == "en"
              ? "$lowConfidenceLineCount of $recognizedLineCount lines may be unclear. Compare the name, strength, Qty, and directions with the bottle."
              : "$lowConfidenceLineCount trong $recognizedLineCount dòng có thể chưa rõ. Hãy đối chiếu tên thuốc, hàm lượng, Qty và cách dùng với chai thuốc.")
        : (language == "en"
              ? "Common OCR spelling errors are cleaned conservatively. Always compare the result with the bottle before saving."
              : "Một số lỗi đọc chữ phổ biến được sửa thận trọng. Luôn đối chiếu kết quả với chai thuốc trước khi lưu.");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasUnclearLines
                ? Icons.warning_amber_rounded
                : Icons.fact_check_outlined,
            color: color,
            size: 21,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              "$title\n$message",
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CameraScanGuidePage extends StatelessWidget {
  const CameraScanGuidePage({super.key});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 700;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF172033),
              Color.alphaBlend(
                AppTheme.primaryColor.withValues(alpha: 0.52),
                const Color(0xFF172033),
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr("Camera guide", "Hướng dẫn camera"),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                  child: Center(child: CameraGuideIllustration()),
                ),
              ),
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  compact ? 18 : 24,
                  compact ? 18 : 24,
                  compact ? 18 : 24,
                  (compact ? 18 : 24) +
                      MediaQuery.viewPaddingOf(context).bottom,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr("Capture the whole label", "Chụp trọn nhãn thuốc"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF172033),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 14),
                    _CameraGuideTip(
                      icon: Icons.light_mode_rounded,
                      text: tr(
                        "Use bright, even light",
                        "Dùng ánh sáng rõ, đều",
                      ),
                    ),
                    const SizedBox(height: 7),
                    _CameraGuideTip(
                      icon: Icons.crop_free_rounded,
                      text: tr(
                        "Keep every label edge inside the frame",
                        "Đặt toàn bộ mép nhãn trong khung hình",
                      ),
                    ),
                    const SizedBox(height: 7),
                    _CameraGuideTip(
                      icon: Icons.front_hand_rounded,
                      text: tr(
                        "Hold still until the photo is clear",
                        "Giữ yên đến khi ảnh rõ nét",
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 22),
                    SizedBox(
                      height: compact ? 52 : 58,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            tr("Open Camera", "Mở camera"),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
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
    );
  }
}

class _CameraGuideTip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CameraGuideTip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTheme.lightColor,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class CameraGuideIllustration extends StatelessWidget {
  const CameraGuideIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 330,
        height: 300,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 20,
              top: 88,
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 42,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 6),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        4,
                        (_) => Container(
                          width: 5,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 92,
                    height: 112,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        _GuideLabelLine(color: Color(0xFF22C55E), width: 58),
                        SizedBox(height: 12),
                        _GuideLabelLine(color: Color(0xFFFACC15), width: 58),
                        SizedBox(height: 12),
                        _GuideLabelLine(color: Color(0xFFFB7185), width: 42),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 34,
              top: 24,
              child: Container(
                width: 145,
                height: 238,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 7),
                  borderRadius: BorderRadius.circular(27),
                ),
                child: Align(
                  alignment: const Alignment(0, -0.84),
                  child: Container(
                    width: 45,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 80,
              top: 106,
              child: Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: Color(0xFF10D991),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 52,
                ),
              ),
            ),
            const Positioned(
              right: 0,
              bottom: 12,
              child: Icon(
                Icons.touch_app_outlined,
                color: Colors.white,
                size: 112,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideLabelLine extends StatelessWidget {
  final Color color;
  final double width;

  const _GuideLabelLine({required this.color, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class ScanQualityTipCard extends StatelessWidget {
  const ScanQualityTipCard({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.18),
          width: 1.3,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.lightColor,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.tips_and_updates_rounded,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              language == "en"
                  ? (Platform.isMacOS
                        ? "Scan tip: choose 2–3 clear, close photos. Include the medication name, strength, Qty, directions, pharmacy name, and phone number."
                        : "Scan tip: take 2–3 clear photos. Include the medication name, dosage, Qty, directions, pharmacy name, and pharmacy phone number.")
                  : (Platform.isMacOS
                        ? "Mẹo quét: chọn 2–3 ảnh rõ, chụp gần. Bao gồm tên thuốc, hàm lượng, Qty, hướng dẫn, tên và số điện thoại nhà thuốc."
                        : "Mẹo quét: chụp 2–3 ảnh rõ. Bao gồm tên thuốc, liều lượng, Qty, hướng dẫn, tên nhà thuốc và số điện thoại."),
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanPreviewCard extends StatelessWidget {
  final List<XFile> selectedImages;
  final Future<void> Function(int index) onRemoveImage;
  final VoidCallback onClearAll;

  const ScanPreviewCard({
    super.key,
    required this.selectedImages,
    required this.onRemoveImage,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final hasImages = selectedImages.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: hasImages
              ? AppTheme.primaryColor.withValues(alpha: 0.35)
              : AppTheme.primaryColor.withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: hasImages ? buildImages(context) : buildEmpty(context),
    );
  }

  Widget buildImages(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.file(
            File(selectedImages.last.path),
            width: double.infinity,
            height: 250,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: AppTheme.primaryColor,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selectedImages.length == 1
                    ? (language == "en" ? "1 photo added" : "Đã thêm 1 ảnh")
                    : (language == "en"
                          ? "${selectedImages.length} photos added"
                          : "Đã thêm ${selectedImages.length} ảnh"),
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onClearAll,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFEF4444),
              ),
              label: Text(
                language == "en" ? "Clear" : "Xoá",
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: selectedImages.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(selectedImages[index].path),
                        width: 82,
                        height: 82,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: () {
                          onRemoveImage(index);
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          language == "en"
              ? "Tip: take one photo of the medication name, one of the directions, and one of the pharmacy phone."
              : "Mẹo: chụp một ảnh tên thuốc, một ảnh hướng dẫn, và một ảnh số nhà thuốc.",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF667085),
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget buildEmpty(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: AppTheme.lightColor,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Icon(
            Icons.document_scanner_rounded,
            color: AppTheme.primaryColor,
            size: 50,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          AppLanguage.text("noImageSelected"),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E2A3A),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          language == "en"
              ? (Platform.isMacOS
                    ? "Choose multiple clear photos if the label wraps around the bottle."
                    : "Take multiple clear photos if the label wraps around the bottle.")
              : (Platform.isMacOS
                    ? "Chọn nhiều ảnh rõ nếu nhãn thuốc quấn quanh chai."
                    : "Chụp nhiều ảnh rõ nếu nhãn thuốc bị quấn quanh chai."),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF667085),
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class ScanSuccessCard extends StatelessWidget {
  final int imageCount;

  const ScanSuccessCard({super.key, required this.imageCount});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF22C55E).withValues(alpha: 0.28),
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              language == "en"
                  ? "Ready. The app combined text from $imageCount photo(s). Review and edit before continuing."
                  : "Sẵn sàng. Ứng dụng đã ghép chữ từ $imageCount ảnh. Hãy kiểm tra và sửa trước khi tiếp tục.",
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1E2A3A),
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

class ReadingTextCard extends StatelessWidget {
  final int imageCount;

  const ReadingTextCard({super.key, required this.imageCount});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.28),
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              color: AppTheme.primaryColor,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              language == "en"
                  ? "Reading and combining text from $imageCount photo(s)..."
                  : "Đang đọc và ghép chữ từ $imageCount ảnh...",
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1E2A3A),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ConfirmScannedInfoCard extends StatelessWidget {
  final int imageCount;
  final bool hasScannedText;
  final TextEditingController nameController;
  final TextEditingController dosageController;
  final TextEditingController quantityController;
  TextEditingController get qtyController => quantityController;
  final TextEditingController pharmacyNameController;
  final TextEditingController pharmacyAddressController;
  final TextEditingController pharmacyPhoneController;
  final TextEditingController instructionsController;
  final TextEditingController notesController;
  final String scannedText;
  final bool showRawText;
  final VoidCallback onToggleRawText;
  final VoidCallback onReadAgain;
  final FocusNode medicationNameFocusNode;
  final FocusNode dosageFocusNode;
  final bool medicationSuggestionsOpen;
  final bool isSearchingRxNorm;
  final List<RxNormSuggestion> medicationSuggestions;
  final String rxNormSearchMessage;
  final Map<String, String> scanEvidence;
  final int recognizedOcrLineCount;
  final int lowConfidenceOcrLineCount;
  final VoidCallback onDetailsChanged;
  final ValueChanged<String> onMedicationNameChanged;
  final VoidCallback onMedicationSuggestionInteractionStart;
  final ValueChanged<RxNormSuggestion> onSelectMedication;

  const ConfirmScannedInfoCard({
    super.key,
    required this.imageCount,
    required this.hasScannedText,
    required this.nameController,
    required this.dosageController,
    required this.quantityController,
    required this.pharmacyNameController,
    required this.pharmacyAddressController,
    required this.pharmacyPhoneController,
    required this.instructionsController,
    required this.notesController,
    required this.scannedText,
    required this.showRawText,
    required this.onToggleRawText,
    required this.onReadAgain,
    required this.medicationNameFocusNode,
    required this.dosageFocusNode,
    required this.medicationSuggestionsOpen,
    required this.isSearchingRxNorm,
    required this.medicationSuggestions,
    required this.rxNormSearchMessage,
    required this.scanEvidence,
    required this.recognizedOcrLineCount,
    required this.lowConfidenceOcrLineCount,
    required this.onDetailsChanged,
    required this.onMedicationNameChanged,
    required this.onMedicationSuggestionInteractionStart,
    required this.onSelectMedication,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.20),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasScannedText
                    ? Icons.edit_note_rounded
                    : Icons.search_off_rounded,
                color: hasScannedText
                    ? AppTheme.primaryColor
                    : const Color(0xFFF59E0B),
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  language == "en"
                      ? "Confirm Combined Information"
                      : "Xác Nhận Thông Tin Đã Ghép",
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color(0xFF1E2A3A),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            language == "en"
                ? "OCR combined $imageCount photo(s). Edit the fields below before continuing."
                : "OCR đã ghép $imageCount ảnh. Hãy sửa thông tin bên dưới trước khi tiếp tục.",
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF667085),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (recognizedOcrLineCount > 0) ...[
            const SizedBox(height: 12),
            OcrAccuracyCard(
              recognizedLineCount: recognizedOcrLineCount,
              lowConfidenceLineCount: lowConfidenceOcrLineCount,
            ),
          ],
          const SizedBox(height: 18),
          EditableScanField(
            controller: nameController,
            label: AppLanguage.text("medicationName"),
            icon: Icons.medication_rounded,
            hintText: language == "en"
                ? "Start typing, for example: Tyle..."
                : "Bắt đầu nhập, ví dụ: Tyle...",
            focusNode: medicationNameFocusNode,
            onChanged: onMedicationNameChanged,
            textInputAction: TextInputAction.search,
          ),
          if (medicationSuggestionsOpen &&
              nameController.text.trim().isNotEmpty &&
              (medicationSuggestions.isNotEmpty ||
                  isSearchingRxNorm ||
                  rxNormSearchMessage.isNotEmpty)) ...[
            const SizedBox(height: 8),
            MedicationSuggestionList(
              query: nameController.text,
              suggestions: medicationSuggestions,
              isSearching: isSearchingRxNorm,
              message: rxNormSearchMessage,
              onInteractionStart: onMedicationSuggestionInteractionStart,
              onSelected: onSelectMedication,
            ),
          ],
          const SizedBox(height: 14),
          EditableScanField(
            controller: dosageController,
            label: AppLanguage.text("dosage"),
            icon: Icons.scale_rounded,
            hintText: language == "en" ? "Example: 100 MG" : "Ví dụ: 100 MG",
            focusNode: dosageFocusNode,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          EditableScanField(
            controller: qtyController,
            label: language == "en" ? "Quantity (Qty)" : "Số lượng (Qty)",
            icon: Icons.inventory_2_rounded,
            hintText: language == "en" ? "Example: 30" : "Ví dụ: 30",
          ),
          if (qtyController.text.trim().isEmpty) ...[
            const SizedBox(height: 10),
            const QuantityScanTipCard(),
          ],
          const SizedBox(height: 14),
          HealthcarePlaceSearchField(
            nameController: pharmacyNameController,
            addressController: pharmacyAddressController,
            phoneController: pharmacyPhoneController,
            label: language == "en"
                ? "Care Provider (Optional)"
                : "Nhà Thuốc / Cơ Sở (Không Bắt Buộc)",
            hintText: language == "en"
                ? "Pharmacy, clinic, hospital, or doctor"
                : "Nhà thuốc, phòng khám, bệnh viện hoặc bác sĩ",
            borderRadius: 16,
            fillColor: AppTheme.lightColor.withValues(alpha: 0.35),
            showHelperText: false,
          ),
          const SizedBox(height: 14),
          EditableScanField(
            controller: pharmacyPhoneController,
            label: language == "en"
                ? "Provider Phone"
                : "Số Điện Thoại Cơ Sở / Bác Sĩ",
            icon: Icons.phone_rounded,
            hintText: language == "en"
                ? "Example: (714) 123-4567"
                : "Ví dụ: (714) 123-4567",
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          EditableScanField(
            controller: instructionsController,
            label: AppLanguage.text("instructions"),
            icon: Icons.description_rounded,
            hintText: language == "en"
                ? "Example: Take 1 capsule every 4 hours. Small spelling mistakes are okay."
                : "Ví dụ: Uống 1 viên mỗi 4 giờ. Có thể nhập sai chính tả nhẹ.",
            maxLines: 3,
            onChanged: (_) => onDetailsChanged(),
          ),
          const SizedBox(height: 14),
          EditableScanField(
            controller: notesController,
            label: language == "en" ? "Description / Notes" : "Mô Tả / Ghi Chú",
            icon: Icons.warning_amber_rounded,
            hintText: language == "en"
                ? "Safety notes or directions that were printed separately"
                : "Ghi chú an toàn hoặc hướng dẫn được in ở phần khác",
            maxLines: 3,
            onChanged: (_) => onDetailsChanged(),
          ),
          const SizedBox(height: 10),
          ScanSchedulePreviewCard(
            instructions: instructionsController.text,
            notes: notesController.text,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReadAgain,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.45),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    language == "en" ? "Analyze Again" : "Phân Tích Lại",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onToggleRawText,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF667085),
                    side: BorderSide(
                      color: const Color(0xFF667085).withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    showRawText
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  label: Text(
                    showRawText
                        ? (language == "en" ? "Hide Text" : "Ẩn Chữ")
                        : (language == "en" ? "Raw Text" : "Chữ Gốc"),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          if (showRawText) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.lightColor.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                scannedText.trim().isEmpty
                    ? (language == "en"
                          ? "No text found."
                          : "Không tìm thấy chữ.")
                    : scannedText,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF667085),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ScanSchedulePreviewCard extends StatelessWidget {
  final String instructions;
  final String notes;

  const ScanSchedulePreviewCard({
    super.key,
    required this.instructions,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final scheduleDirections = TimeHelper.selectScheduleDirections(
      instructions: instructions,
      notes: notes,
    );
    final doseDirections = TimeHelper.combineDoseDirections(
      instructions: instructions,
      notes: notes,
    );
    final times = TimeHelper.generateReminderTimesFromInstructions(
      scheduleDirections,
    );
    final doseAmount = TimeHelper.getDoseAmountFromInstructions(doseDirections);
    final instructionInterpretation = TimeHelper.interpretInstruction(
      scheduleDirections,
    );
    final fromNotes =
        notes.trim().isNotEmpty && scheduleDirections == notes.trim();
    final isAsNeeded = TimeHelper.isAsNeededInstruction(scheduleDirections);
    final needsManualReview =
        scheduleDirections.isNotEmpty && !isAsNeeded && times.isEmpty;

    String title;
    String message;
    Color color;
    IconData icon;

    if (scheduleDirections.isEmpty) {
      title = language == "en"
          ? "No timing detected yet"
          : "Chưa nhận diện thời gian";
      message = language == "en"
          ? "Type timing in Instructions or Description/Notes."
          : "Nhập thời gian trong Hướng dẫn hoặc Mô tả/Ghi chú.";
      color = const Color(0xFFF59E0B);
      icon = Icons.info_outline_rounded;
    } else if (isAsNeeded) {
      title = language == "en"
          ? "As-needed direction"
          : "Hướng dẫn dùng khi cần";
      message = language == "en"
          ? "Dose amount: $doseAmount. No fixed reminder time will be guessed."
          : "Số lượng mỗi liều: $doseAmount. Ứng dụng không tự đoán giờ nhắc cố định.";
      color = const Color(0xFFF59E0B);
      icon = Icons.info_outline_rounded;
    } else if (needsManualReview) {
      title = language == "en"
          ? "Manual review needed"
          : "Cần kiểm tra thủ công";
      message = language == "en"
          ? "Dose amount: $doseAmount. Add and verify the reminder time after continuing."
          : "Số lượng mỗi liều: $doseAmount. Hãy thêm và xác minh giờ nhắc sau khi tiếp tục.";
      color = const Color(0xFFF59E0B);
      icon = Icons.rule_rounded;
    } else {
      final timeText = times.map(TimeHelper.formatTimeForDisplay).join(", ");
      title = language == "en"
          ? "Detected reminder schedule"
          : "Đã nhận diện lịch nhắc";
      message = language == "en"
          ? "Dose amount: $doseAmount • $timeText • Read from ${fromNotes ? "Description/Notes" : "Instructions"}."
          : "Số lượng mỗi liều: $doseAmount • $timeText • Đọc từ ${fromNotes ? "Mô tả/Ghi chú" : "Hướng dẫn"}.";
      color = const Color(0xFF22C55E);
      icon = Icons.schedule_rounded;
    }

    if (instructionInterpretation.usedSpellingAssistance) {
      final correctionSummary = instructionInterpretation.correctionSummary();

      message = language == "en"
          ? "$message\n\nSpelling help used: $correctionSummary. Original label wording was kept—verify the result."
          : "$message\n\nĐã hỗ trợ chính tả: $correctionSummary. Nội dung gốc trên nhãn vẫn được giữ—hãy kiểm tra kết quả.";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              "$title\n$message",
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanEvidenceCard extends StatelessWidget {
  final Map<String, String> evidence;

  const ScanEvidenceCard({super.key, required this.evidence});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF22C55E).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_search_rounded, color: Color(0xFF15803D)),
              const SizedBox(width: 8),
              Text(
                language == "en" ? "What OCR used" : "Nội dung OCR đã dùng",
                style: const TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...evidence.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                "${entry.key}: “${entry.value}”",
                style: const TextStyle(
                  color: Color(0xFF475467),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class InstructionExamplesCard extends StatelessWidget {
  const InstructionExamplesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    final examples = language == "en"
        ? [
            "1 capsule every 4 hours",
            "1 tablet twice daily with food",
            "2 capsules once daily after food",
            "1 tablet every morning and at bedtime",
            "1 tablet at 8 AM and 8 PM",
          ]
        : [
            "1 viên mỗi 4 giờ",
            "1 viên 2 lần mỗi ngày cùng thức ăn",
            "2 viên mỗi ngày sau ăn",
            "1 viên mỗi sáng và trước khi ngủ",
            "1 viên lúc 8 giờ và 20 giờ",
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFF2563EB).withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF2563EB),
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  language == "en"
                      ? "Recognized schedule examples"
                      : "Ví dụ lịch có thể nhận diện",
                  style: const TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ...examples.map((example) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                "• $example",
                style: const TextStyle(
                  color: Color(0xFF475467),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            language == "en"
                ? "Common spelling mistakes are interpreted without changing your text. Ranges, conflicting before/after-meal wording, maximum limits, changing doses, and weekly directions are left for manual review."
                : "Lỗi chính tả phổ biến được diễn giải mà không thay đổi nội dung bạn nhập. Khoảng liều, hướng dẫn trước/sau bữa ăn bị mâu thuẫn, giới hạn tối đa, liều thay đổi và lịch theo tuần sẽ được để kiểm tra thủ công.",
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class QuantityScanTipCard extends StatelessWidget {
  const QuantityScanTipCard({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFF59E0B),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              language == "en"
                  ? "Qty not found—enter the number printed after Qty."
                  : "Chưa thấy Qty—hãy nhập số in sau chữ Qty.",
              style: const TextStyle(
                color: Color(0xFF92400E),
                height: 1.3,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PharmacyScanTipCard extends StatelessWidget {
  const PharmacyScanTipCard({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF22C55E).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.phone_in_talk_rounded,
            color: Color(0xFF22C55E),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              language == "en"
                  ? "Search and choose the exact location. Its phone number fills automatically when listed."
                  : "Tìm và chọn đúng cơ sở. Số điện thoại sẽ tự điền khi có thông tin.",
              style: const TextStyle(
                color: Color(0xFF166534),
                height: 1.3,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EditableScanField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  const EditableScanField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.hintText,
    this.maxLines = 1,
    this.keyboardType,
    this.focusNode,
    this.onChanged,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, color: AppTheme.primaryColor),
        filled: true,
        fillColor: AppTheme.lightColor.withValues(alpha: 0.35),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppTheme.primaryColor.withValues(alpha: 0.18),
            width: 1.4,
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class ScanSafetyNote extends StatelessWidget {
  const ScanSafetyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.28),
          width: 1.4,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              language == "en"
                  ? "OCR may make mistakes. Always double-check medication, pharmacy, and phone information before saving."
                  : "OCR có thể đọc sai. Luôn kiểm tra kỹ thông tin thuốc, nhà thuốc và số điện thoại trước khi lưu.",
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1E2A3A),
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
