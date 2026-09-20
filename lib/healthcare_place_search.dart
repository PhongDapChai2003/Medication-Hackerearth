import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'medication_storage.dart';

enum HealthcarePlaceSource { saved, onDevice, appleMaps }

class HealthcarePlaceSuggestion {
  final String name;
  final String address;
  final String phone;
  final String website;
  final String category;
  final String country;
  final List<String> aliases;
  final HealthcarePlaceSource source;
  final double? latitude;
  final double? longitude;

  const HealthcarePlaceSuggestion({
    required this.name,
    this.address = "",
    this.phone = "",
    this.website = "",
    this.category = "healthcare",
    this.country = "",
    this.aliases = const <String>[],
    this.source = HealthcarePlaceSource.onDevice,
    this.latitude,
    this.longitude,
  });

  factory HealthcarePlaceSuggestion.fromPlatformMap(Map<dynamic, dynamic> map) {
    return HealthcarePlaceSuggestion(
      name: (map["name"] ?? "").toString().trim(),
      address: (map["address"] ?? "").toString().trim(),
      phone: (map["phone"] ?? "").toString().trim(),
      website: (map["website"] ?? "").toString().trim(),
      category: (map["category"] ?? "healthcare").toString().trim(),
      country: (map["country"] ?? "").toString().trim(),
      source: HealthcarePlaceSource.appleMaps,
      latitude: _readDouble(map["latitude"]),
      longitude: _readDouble(map["longitude"]),
    );
  }

  static double? _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? "");
  }

  String get comparisonKey {
    final cleanName = HealthcarePlaceService.normalize(name);
    final cleanAddress = HealthcarePlaceService.normalize(address);

    if (cleanAddress.isNotEmpty) {
      return "$cleanName|$cleanAddress";
    }

    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), "");
    return "$cleanName|$cleanPhone";
  }

  String get searchableText {
    return HealthcarePlaceService.normalize(
      <String>[name, address, country, category, ...aliases].join(" "),
    );
  }
}

class HealthcarePlaceService {
  static const MethodChannel _channel = MethodChannel(
    "medication_reminder/healthcare_places",
  );

  static const List<HealthcarePlaceSuggestion> commonPlaces =
      <HealthcarePlaceSuggestion>[
        HealthcarePlaceSuggestion(
          name: "CVS Pharmacy",
          category: "pharmacy",
          country: "United States",
          aliases: <String>["CVS", "CVS Health", "Target CVS"],
        ),
        HealthcarePlaceSuggestion(
          name: "Walgreens Pharmacy",
          category: "pharmacy",
          country: "United States",
          aliases: <String>["Walgreens"],
        ),
        HealthcarePlaceSuggestion(
          name: "Rite Aid Pharmacy",
          category: "pharmacy",
          country: "United States",
          aliases: <String>["Rite Aid"],
        ),
        HealthcarePlaceSuggestion(
          name: "Walmart Pharmacy",
          category: "pharmacy",
          country: "United States",
          aliases: <String>["Walmart"],
        ),
        HealthcarePlaceSuggestion(
          name: "Costco Pharmacy",
          category: "pharmacy",
          country: "United States / Canada",
          aliases: <String>["Costco"],
        ),
        HealthcarePlaceSuggestion(
          name: "Kaiser Permanente",
          category: "hospital",
          country: "United States",
          aliases: <String>["Kaiser", "Kaiser Pharmacy", "Kaiser Hospital"],
        ),
        HealthcarePlaceSuggestion(
          name: "Mayo Clinic",
          category: "clinic",
          country: "United States",
          aliases: <String>["Mayo"],
        ),
        HealthcarePlaceSuggestion(
          name: "Cleveland Clinic",
          category: "clinic",
          country: "United States",
          aliases: <String>["Cleveland Hospital"],
        ),
        HealthcarePlaceSuggestion(
          name: "Dr. Kelvin Mai, D.O. — Garden Grove",
          address: "12666 Brookhurst St Ste 130, Garden Grove, CA 92840",
          phone: "(714) 332-1069",
          category: "doctor",
          country: "United States",
          aliases: <String>[
            "Dr Kelvin Mai DO",
            "Kelvin Mai Do",
            "Kelvin Mai D.O.",
            "Kelvin D Mai DO",
            "Doctor Kelvin Mai",
          ],
        ),
        HealthcarePlaceSuggestion(
          name: "Dr. Kelvin Mai, D.O. — Santa Ana",
          address: "1002 N Fairview St, Santa Ana, CA 92703",
          phone: "(714) 332-1069",
          category: "doctor",
          country: "United States",
          aliases: <String>[
            "Dr Kelvin Mai DO Santa Ana",
            "Kelvin Mai Do Santa Ana",
            "Kelvin D Mai DO",
            "Doctor Kelvin Mai",
          ],
        ),
        HealthcarePlaceSuggestion(
          name: "Shoppers Drug Mart",
          category: "pharmacy",
          country: "Canada",
          aliases: <String>["Pharmaprix", "Shoppers Pharmacy"],
        ),
        HealthcarePlaceSuggestion(
          name: "Rexall Pharmacy",
          category: "pharmacy",
          country: "Canada",
          aliases: <String>["Rexall"],
        ),
        HealthcarePlaceSuggestion(
          name: "London Drugs Pharmacy",
          category: "pharmacy",
          country: "Canada",
          aliases: <String>["London Drugs"],
        ),
        HealthcarePlaceSuggestion(
          name: "Boots Pharmacy",
          category: "pharmacy",
          country: "United Kingdom / Ireland",
          aliases: <String>["Boots"],
        ),
        HealthcarePlaceSuggestion(
          name: "Superdrug Pharmacy",
          category: "pharmacy",
          country: "United Kingdom",
          aliases: <String>["Superdrug"],
        ),
        HealthcarePlaceSuggestion(
          name: "NHS Hospital",
          category: "hospital",
          country: "United Kingdom",
          aliases: <String>["NHS", "National Health Service"],
        ),
        HealthcarePlaceSuggestion(
          name: "Chemist Warehouse",
          category: "pharmacy",
          country: "Australia / New Zealand",
          aliases: <String>["Chemist Warehouse Pharmacy"],
        ),
        HealthcarePlaceSuggestion(
          name: "Priceline Pharmacy",
          category: "pharmacy",
          country: "Australia",
          aliases: <String>["Priceline"],
        ),
        HealthcarePlaceSuggestion(
          name: "TerryWhite Chemmart",
          category: "pharmacy",
          country: "Australia",
          aliases: <String>["Terry White Pharmacy"],
        ),
        HealthcarePlaceSuggestion(
          name: "Pharmacity",
          category: "pharmacy",
          country: "Vietnam",
          aliases: <String>["Nhà thuốc Pharmacity", "Nha thuoc Pharmacity"],
        ),
        HealthcarePlaceSuggestion(
          name: "Nhà thuốc Long Châu",
          category: "pharmacy",
          country: "Vietnam",
          aliases: <String>[
            "Long Chau",
            "FPT Long Châu",
            "FPT Long Chau",
            "Nhà thuốc FPT Long Châu",
          ],
        ),
        HealthcarePlaceSuggestion(
          name: "Nhà thuốc An Khang",
          category: "pharmacy",
          country: "Vietnam",
          aliases: <String>["An Khang", "Nha thuoc An Khang"],
        ),
        HealthcarePlaceSuggestion(
          name: "Vinmec International Hospital",
          category: "hospital",
          country: "Vietnam",
          aliases: <String>["Vinmec", "Bệnh viện Vinmec", "Benh vien Vinmec"],
        ),
        HealthcarePlaceSuggestion(
          name: "Hoàn Mỹ Medical Corporation",
          category: "hospital",
          country: "Vietnam",
          aliases: <String>[
            "Hoan My",
            "Bệnh viện Hoàn Mỹ",
            "Benh vien Hoan My",
          ],
        ),
        HealthcarePlaceSuggestion(
          name: "Bệnh viện Chợ Rẫy",
          category: "hospital",
          country: "Vietnam",
          aliases: <String>["Cho Ray Hospital", "Benh vien Cho Ray"],
        ),
        HealthcarePlaceSuggestion(
          name: "Bệnh viện Bạch Mai",
          category: "hospital",
          country: "Vietnam",
          aliases: <String>["Bach Mai Hospital", "Benh vien Bach Mai"],
        ),
        HealthcarePlaceSuggestion(
          name: "Watsons Pharmacy",
          category: "pharmacy",
          country: "Asia / Europe",
          aliases: <String>["Watsons", "A.S. Watson"],
        ),
        HealthcarePlaceSuggestion(
          name: "Guardian Pharmacy",
          category: "pharmacy",
          country: "Southeast Asia",
          aliases: <String>["Guardian"],
        ),
        HealthcarePlaceSuggestion(
          name: "Raffles Hospital",
          category: "hospital",
          country: "Singapore",
          aliases: <String>["Raffles Medical", "Raffles Medical Group"],
        ),
        HealthcarePlaceSuggestion(
          name: "Matsumoto Kiyoshi",
          category: "pharmacy",
          country: "Japan",
          aliases: <String>["Matsukiyo", "マツモトキヨシ"],
        ),
        HealthcarePlaceSuggestion(
          name: "Welcia Pharmacy",
          category: "pharmacy",
          country: "Japan",
          aliases: <String>["Welcia", "ウエルシア"],
        ),
        HealthcarePlaceSuggestion(
          name: "Apollo Pharmacy",
          category: "pharmacy",
          country: "India",
          aliases: <String>["Apollo"],
        ),
        HealthcarePlaceSuggestion(
          name: "MedPlus Pharmacy",
          category: "pharmacy",
          country: "India",
          aliases: <String>["MedPlus"],
        ),
        HealthcarePlaceSuggestion(
          name: "Apollo Hospitals",
          category: "hospital",
          country: "India",
          aliases: <String>["Apollo Hospital"],
        ),
        HealthcarePlaceSuggestion(
          name: "Fortis Healthcare",
          category: "hospital",
          country: "India",
          aliases: <String>["Fortis Hospital"],
        ),
        HealthcarePlaceSuggestion(
          name: "Bangkok Hospital",
          category: "hospital",
          country: "Thailand",
          aliases: <String>["Bangkok Dusit Medical Services", "BDMS"],
        ),
        HealthcarePlaceSuggestion(
          name: "Fascino Pharmacy",
          category: "pharmacy",
          country: "Thailand",
          aliases: <String>["Fascino"],
        ),
        HealthcarePlaceSuggestion(
          name: "Mercury Drug",
          category: "pharmacy",
          country: "Philippines",
          aliases: <String>["Mercury Pharmacy"],
        ),
        HealthcarePlaceSuggestion(
          name: "The Medical City",
          category: "hospital",
          country: "Philippines",
          aliases: <String>["Medical City Hospital"],
        ),
        HealthcarePlaceSuggestion(
          name: "Kimia Farma",
          category: "pharmacy",
          country: "Indonesia",
          aliases: <String>["Apotek Kimia Farma"],
        ),
        HealthcarePlaceSuggestion(
          name: "Guardian Malaysia",
          category: "pharmacy",
          country: "Malaysia",
          aliases: <String>["Guardian Pharmacy Malaysia"],
        ),
        HealthcarePlaceSuggestion(
          name: "Farmacias del Ahorro",
          category: "pharmacy",
          country: "Mexico",
          aliases: <String>["Farmacia del Ahorro"],
        ),
        HealthcarePlaceSuggestion(
          name: "Farmacias Guadalajara",
          category: "pharmacy",
          country: "Mexico",
          aliases: <String>["Farmacia Guadalajara"],
        ),
        HealthcarePlaceSuggestion(
          name: "Farmacias Similares",
          category: "pharmacy",
          country: "Mexico",
          aliases: <String>["Dr. Simi", "Farmacia Similares"],
        ),
        HealthcarePlaceSuggestion(
          name: "Droga Raia",
          category: "pharmacy",
          country: "Brazil",
          aliases: <String>["Raia Drogasil"],
        ),
        HealthcarePlaceSuggestion(
          name: "Drogasil",
          category: "pharmacy",
          country: "Brazil",
          aliases: <String>["Raia Drogasil"],
        ),
        HealthcarePlaceSuggestion(
          name: "Pague Menos",
          category: "pharmacy",
          country: "Brazil",
          aliases: <String>["Farmácias Pague Menos", "Farmacias Pague Menos"],
        ),
        HealthcarePlaceSuggestion(
          name: "Hospital Israelita Albert Einstein",
          category: "hospital",
          country: "Brazil",
          aliases: <String>["Albert Einstein Hospital"],
        ),
        HealthcarePlaceSuggestion(
          name: "Aster Pharmacy",
          category: "pharmacy",
          country: "United Arab Emirates / Gulf",
          aliases: <String>["Aster"],
        ),
        HealthcarePlaceSuggestion(
          name: "Mediclinic",
          category: "hospital",
          country: "Middle East / Southern Africa",
          aliases: <String>["Mediclinic Hospital"],
        ),
        HealthcarePlaceSuggestion(
          name: "Life Healthcare",
          category: "hospital",
          country: "South Africa",
          aliases: <String>["Life Hospital"],
        ),
        HealthcarePlaceSuggestion(
          name: "Dis-Chem Pharmacy",
          category: "pharmacy",
          country: "South Africa",
          aliases: <String>["Dischem", "Dis-Chem"],
        ),
        HealthcarePlaceSuggestion(
          name: "Clicks Pharmacy",
          category: "pharmacy",
          country: "South Africa",
          aliases: <String>["Clicks"],
        ),
      ];

  static Uri? phoneUri(HealthcarePlaceSuggestion place) {
    final phoneNumber = place.phone.replaceAll(RegExp(r"[^0-9+]"), "");

    if (phoneNumber.isEmpty) {
      return null;
    }

    return Uri(scheme: "tel", path: phoneNumber);
  }

  static Uri? directionsUri(HealthcarePlaceSuggestion place) {
    final destination = place.latitude != null && place.longitude != null
        ? "${place.latitude},${place.longitude}"
        : place.address.trim();

    if (destination.isEmpty) {
      return null;
    }

    return Uri.https("maps.apple.com", "/", <String, String>{
      "daddr": destination,
      "q": place.name,
    });
  }

  static Uri? websiteUri(HealthcarePlaceSuggestion place) {
    final website = place.website.trim();

    if (website.isEmpty) {
      return null;
    }

    final valueWithScheme = website.contains("://")
        ? website
        : "https://$website";
    final uri = Uri.tryParse(valueWithScheme);

    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != "http" && uri.scheme != "https")) {
      return null;
    }

    return uri;
  }

  static String normalize(String value) {
    var normalized = value.toLowerCase();

    const replacements = <String, String>{
      "à": "a",
      "á": "a",
      "ạ": "a",
      "ả": "a",
      "ã": "a",
      "â": "a",
      "ầ": "a",
      "ấ": "a",
      "ậ": "a",
      "ẩ": "a",
      "ẫ": "a",
      "ă": "a",
      "ằ": "a",
      "ắ": "a",
      "ặ": "a",
      "ẳ": "a",
      "ẵ": "a",
      "è": "e",
      "é": "e",
      "ẹ": "e",
      "ẻ": "e",
      "ẽ": "e",
      "ê": "e",
      "ề": "e",
      "ế": "e",
      "ệ": "e",
      "ể": "e",
      "ễ": "e",
      "ì": "i",
      "í": "i",
      "ị": "i",
      "ỉ": "i",
      "ĩ": "i",
      "ò": "o",
      "ó": "o",
      "ọ": "o",
      "ỏ": "o",
      "õ": "o",
      "ô": "o",
      "ồ": "o",
      "ố": "o",
      "ộ": "o",
      "ổ": "o",
      "ỗ": "o",
      "ơ": "o",
      "ờ": "o",
      "ớ": "o",
      "ợ": "o",
      "ở": "o",
      "ỡ": "o",
      "ù": "u",
      "ú": "u",
      "ụ": "u",
      "ủ": "u",
      "ũ": "u",
      "ư": "u",
      "ừ": "u",
      "ứ": "u",
      "ự": "u",
      "ử": "u",
      "ữ": "u",
      "ỳ": "y",
      "ý": "y",
      "ỵ": "y",
      "ỷ": "y",
      "ỹ": "y",
      "đ": "d",
    };

    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }

    return normalized.replaceAll(RegExp(r"[\s\-_,.'’/()]+"), " ").trim();
  }

  static int _matchScore(
    HealthcarePlaceSuggestion place,
    String normalizedQuery,
  ) {
    if (normalizedQuery.isEmpty) {
      return place.source == HealthcarePlaceSource.saved ? 100 : -1;
    }

    final name = normalize(place.name);
    final nameAndAliases = normalize(
      <String>[place.name, ...place.aliases].join(" "),
    );
    final searchable = place.searchableText;
    final queryWords = normalizedQuery
        .split(" ")
        .where((word) => word.isNotEmpty)
        .toList();

    if (name == normalizedQuery) {
      return 1000;
    }

    if (name.startsWith(normalizedQuery)) {
      return 900;
    }

    if (name.split(" ").any((word) => word.startsWith(normalizedQuery))) {
      return 820;
    }

    if (name.contains(normalizedQuery)) {
      return 760;
    }

    if (normalizedQuery.length <= 3) {
      return nameAndAliases
              .split(" ")
              .any((word) => word.startsWith(normalizedQuery))
          ? 700
          : -1;
    }

    if (queryWords.isNotEmpty &&
        queryWords.every((word) => searchable.contains(word))) {
      return 680;
    }

    if (queryWords.any(
      (word) => word.length >= 2 && searchable.contains(word),
    )) {
      return 420;
    }

    return -1;
  }

  static List<HealthcarePlaceSuggestion> findOnDeviceSuggestions(
    String query, {
    List<HealthcarePlaceSuggestion> savedPlaces =
        const <HealthcarePlaceSuggestion>[],
    int maximumResults = 6,
  }) {
    final normalizedQuery = normalize(query);
    final candidates = <HealthcarePlaceSuggestion>[
      ...savedPlaces,
      ...commonPlaces,
    ];
    final scored = <({HealthcarePlaceSuggestion place, int score})>[];

    for (final place in candidates) {
      var score = _matchScore(place, normalizedQuery);

      if (score < 0) {
        continue;
      }

      if (place.source == HealthcarePlaceSource.saved) {
        score += 80;
      }

      scored.add((place: place, score: score));
    }

    scored.sort((first, second) {
      final scoreCompare = second.score.compareTo(first.score);

      if (scoreCompare != 0) {
        return scoreCompare;
      }

      return first.place.name.compareTo(second.place.name);
    });

    final results = <HealthcarePlaceSuggestion>[];
    final seen = <String>{};

    for (final item in scored) {
      if (!seen.add(item.place.comparisonKey)) {
        continue;
      }

      results.add(item.place);

      if (results.length >= maximumResults) {
        break;
      }
    }

    return results;
  }

  static Future<List<HealthcarePlaceSuggestion>> searchAppleMaps(
    String query, {
    int maximumResults = 20,
  }) async {
    final cleanQuery = query.trim();

    if (cleanQuery.length < 2) {
      return const <HealthcarePlaceSuggestion>[];
    }

    final response = await _channel.invokeMethod<List<dynamic>>(
      "searchHealthcarePlaces",
      <String, dynamic>{"query": cleanQuery, "limit": maximumResults},
    );

    if (response == null) {
      return const <HealthcarePlaceSuggestion>[];
    }

    final results = <HealthcarePlaceSuggestion>[];
    final seen = <String>{};

    for (final item in response) {
      if (item is! Map) {
        continue;
      }

      final place = HealthcarePlaceSuggestion.fromPlatformMap(item);

      if (place.name.isEmpty || !seen.add(place.comparisonKey)) {
        continue;
      }

      results.add(place);
    }

    return results;
  }
}

class HealthcarePlaceSearchField extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final String label;
  final String hintText;
  final double borderRadius;
  final Color? fillColor;
  final bool showHelperText;

  const HealthcarePlaceSearchField({
    super.key,
    required this.nameController,
    required this.addressController,
    required this.phoneController,
    required this.label,
    required this.hintText,
    this.borderRadius = 18,
    this.fillColor,
    this.showHelperText = true,
  });

  @override
  State<HealthcarePlaceSearchField> createState() =>
      _HealthcarePlaceSearchFieldState();
}

class _HealthcarePlaceSearchFieldState
    extends State<HealthcarePlaceSearchField> {
  final FocusNode focusNode = FocusNode();

  Timer? searchDebounce;
  Timer? dismissSuggestionsTimer;
  int searchRequest = 0;
  bool isSearching = false;
  bool suggestionsOpen = false;
  String searchMessage = "";
  List<HealthcarePlaceSuggestion> savedPlaces = <HealthcarePlaceSuggestion>[];
  List<HealthcarePlaceSuggestion> onDeviceSuggestions =
      <HealthcarePlaceSuggestion>[];
  List<HealthcarePlaceSuggestion> liveSuggestions =
      <HealthcarePlaceSuggestion>[];

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  void initState() {
    super.initState();
    focusNode.addListener(handleFocusChanged);
    unawaited(loadSavedPlaces());
  }

  Future<void> loadSavedPlaces() async {
    try {
      final medications = await MedicationStorage.loadCurrentLocalMedications();
      final suggestions = <HealthcarePlaceSuggestion>[];
      final seen = <String>{};

      for (final medication in medications) {
        final name = medication.pharmacyName.trim();

        if (name.isEmpty) {
          continue;
        }

        final lowerName = name.toLowerCase();
        final category =
            lowerName.contains("hospital") ||
                lowerName.contains("bệnh viện") ||
                lowerName.contains("benh vien")
            ? "hospital"
            : lowerName.startsWith("dr ") ||
                  lowerName.startsWith("dr.") ||
                  lowerName.contains("doctor") ||
                  lowerName.contains("physician") ||
                  lowerName.contains("bác sĩ") ||
                  lowerName.contains("bac si") ||
                  RegExp(r"\b(m\.?d\.?|d\.?o\.?)\b").hasMatch(lowerName)
            ? "doctor"
            : lowerName.contains("clinic") ||
                  lowerName.contains("phòng khám") ||
                  lowerName.contains("phong kham")
            ? "clinic"
            : "pharmacy";

        final place = HealthcarePlaceSuggestion(
          name: name,
          address: medication.pharmacyAddress.trim(),
          phone: medication.pharmacyPhone.trim(),
          category: category,
          source: HealthcarePlaceSource.saved,
        );

        if (seen.add(place.comparisonKey)) {
          suggestions.add(place);
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        savedPlaces = suggestions;
      });

      if (focusNode.hasFocus) {
        handleQueryChanged(widget.nameController.text);
      }
    } catch (_) {
      // The worldwide search and on-device catalog remain available.
    }
  }

  void handleFocusChanged() {
    if (!mounted) {
      return;
    }

    dismissSuggestionsTimer?.cancel();

    if (!focusNode.hasFocus) {
      searchDebounce?.cancel();
      searchRequest += 1;

      setState(() {
        isSearching = false;
      });

      // Keep the result panel alive long enough for a tap to complete.
      // This is especially important when an existing medication is edited:
      // iOS can move focus before the suggestion row receives its onTap.
      dismissSuggestionsTimer = Timer(const Duration(milliseconds: 240), () {
        if (!mounted || focusNode.hasFocus) {
          return;
        }

        setState(() {
          suggestionsOpen = false;
        });
      });
      return;
    }

    setState(() {
      suggestionsOpen = true;
    });
    handleQueryChanged(widget.nameController.text);
  }

  void handleQueryChanged(String value) {
    searchDebounce?.cancel();
    searchRequest += 1;
    final request = searchRequest;
    final cleanQuery = value.trim();
    final local = HealthcarePlaceService.findOnDeviceSuggestions(
      cleanQuery,
      savedPlaces: savedPlaces,
      maximumResults: 6,
    );

    setState(() {
      suggestionsOpen = focusNode.hasFocus;
      onDeviceSuggestions = local;
      liveSuggestions = <HealthcarePlaceSuggestion>[];
      searchMessage = "";
      isSearching = cleanQuery.length >= 2;
    });

    if (cleanQuery.length < 2) {
      return;
    }

    searchDebounce = Timer(const Duration(milliseconds: 550), () {
      unawaited(searchLivePlaces(cleanQuery, request));
    });
  }

  Future<void> searchLivePlaces(String query, int request) async {
    try {
      final results = await HealthcarePlaceService.searchAppleMaps(
        query,
        maximumResults: 20,
      );

      if (!mounted ||
          request != searchRequest ||
          widget.nameController.text.trim() != query) {
        return;
      }

      setState(() {
        liveSuggestions = results;
        isSearching = false;
        searchMessage = results.isEmpty
            ? tr(
                "No live match. Add a city, ZIP code, or country and try again.",
                "Không tìm thấy trực tuyến. Hãy thêm thành phố, mã ZIP hoặc quốc gia rồi thử lại.",
              )
            : "";
      });
    } on MissingPluginException {
      if (!mounted || request != searchRequest) {
        return;
      }

      setState(() {
        isSearching = false;
        searchMessage = tr(
          "Live worldwide search is available on iPhone and Mac. Saved and common names still work here.",
          "Tìm kiếm trực tuyến toàn thế giới hỗ trợ trên iPhone và Mac. Tên đã lưu và tên phổ biến vẫn dùng được tại đây.",
        );
      });
    } on PlatformException {
      if (!mounted || request != searchRequest) {
        return;
      }

      setState(() {
        isSearching = false;
        searchMessage = tr(
          "Live place search is temporarily unavailable. Check internet and try again.",
          "Tìm kiếm địa điểm trực tuyến tạm thời không khả dụng. Hãy kiểm tra mạng rồi thử lại.",
        );
      });
    } catch (_) {
      if (!mounted || request != searchRequest) {
        return;
      }

      setState(() {
        isSearching = false;
        searchMessage = tr(
          "Live place search is temporarily unavailable. Common names still work.",
          "Tìm kiếm địa điểm trực tuyến tạm thời không khả dụng. Tên phổ biến vẫn dùng được.",
        );
      });
    }
  }

  List<HealthcarePlaceSuggestion> get visibleSuggestions {
    final combined = <HealthcarePlaceSuggestion>[];
    final seen = <String>{};

    for (final place in <HealthcarePlaceSuggestion>[
      ...savedPlaces.where((place) {
        return HealthcarePlaceService._matchScore(
              place,
              HealthcarePlaceService.normalize(widget.nameController.text),
            ) >=
            0;
      }),
      ...onDeviceSuggestions.where((place) {
        return place.address.isNotEmpty || place.phone.isNotEmpty;
      }),
      ...liveSuggestions,
      ...onDeviceSuggestions.where((place) {
        return place.address.isEmpty && place.phone.isEmpty;
      }),
    ]) {
      if (!seen.add(place.comparisonKey)) {
        continue;
      }

      combined.add(place);

      if (combined.length >= 20) {
        break;
      }
    }

    return combined;
  }

  void selectPlace(HealthcarePlaceSuggestion place) {
    searchDebounce?.cancel();
    dismissSuggestionsTimer?.cancel();
    searchRequest += 1;

    widget.nameController.value = TextEditingValue(
      text: place.name,
      selection: TextSelection.collapsed(offset: place.name.length),
    );
    widget.addressController.text = place.address;
    widget.phoneController.text = place.phone;

    setState(() {
      suggestionsOpen = false;
      onDeviceSuggestions = <HealthcarePlaceSuggestion>[];
      liveSuggestions = <HealthcarePlaceSuggestion>[];
      searchMessage = "";
      isSearching = false;
    });

    focusNode.unfocus();

    final detailsFilled = <String>[
      if (place.address.isNotEmpty) tr("address", "địa chỉ"),
      if (place.phone.isNotEmpty) tr("phone", "số điện thoại"),
    ];
    final selectionMessage = detailsFilled.isEmpty
        ? tr(
            "Selected ${place.name}. Add its address or phone if you have it.",
            "Đã chọn ${place.name}. Hãy thêm địa chỉ hoặc số điện thoại nếu có.",
          )
        : tr(
            "Selected ${place.name}. Filled ${detailsFilled.join(" and ")}.",
            "Đã chọn ${place.name}. Đã điền ${detailsFilled.join(" và ")}.",
          );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(selectionMessage)));
  }

  String categoryLabel(HealthcarePlaceSuggestion place) {
    switch (place.category.toLowerCase()) {
      case "pharmacy":
        return tr("Pharmacy", "Nhà thuốc");
      case "hospital":
        return tr("Hospital", "Bệnh viện");
      case "clinic":
        return tr("Clinic", "Phòng khám");
      case "doctor":
        return tr("Doctor / Provider", "Bác sĩ / Người chăm sóc");
      default:
        return tr("Healthcare", "Y tế");
    }
  }

  String sourceLabel(HealthcarePlaceSuggestion place) {
    switch (place.source) {
      case HealthcarePlaceSource.saved:
        return tr("Saved", "Đã lưu");
      case HealthcarePlaceSource.appleMaps:
        return "Apple Maps";
      case HealthcarePlaceSource.onDevice:
        return tr("Common name", "Tên phổ biến");
    }
  }

  IconData placeIcon(HealthcarePlaceSuggestion place) {
    switch (place.category.toLowerCase()) {
      case "hospital":
        return Icons.local_hospital_rounded;
      case "clinic":
        return Icons.medical_services_rounded;
      case "doctor":
        return Icons.person_search_rounded;
      default:
        return Icons.local_pharmacy_rounded;
    }
  }

  TextSpan highlightedName(String value) {
    final cleanQuery = widget.nameController.text.trim();
    final matchIndex = value.toLowerCase().indexOf(cleanQuery.toLowerCase());

    if (cleanQuery.isEmpty || matchIndex < 0) {
      return TextSpan(text: value);
    }

    final matchEnd = matchIndex + cleanQuery.length;

    return TextSpan(
      children: <InlineSpan>[
        if (matchIndex > 0) TextSpan(text: value.substring(0, matchIndex)),
        TextSpan(
          text: value.substring(matchIndex, matchEnd),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        if (matchEnd < value.length) TextSpan(text: value.substring(matchEnd)),
      ],
    );
  }

  Future<void> openPlaceAction(
    Uri uri, {
    required String unavailableEnglish,
    required String unavailableVietnamese,
  }) async {
    dismissSuggestionsTimer?.cancel();

    try {
      final didOpen = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (didOpen || !mounted) {
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(unavailableEnglish, unavailableVietnamese))),
    );
  }

  Widget placeActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryColor,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.24)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget buildSuggestionItem(HealthcarePlaceSuggestion place) {
    final phoneUri = HealthcarePlaceService.phoneUri(place);
    final directionsUri = HealthcarePlaceService.directionsUri(place);
    final websiteUri = HealthcarePlaceService.websiteUri(place);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          onTapDown: (_) {
            dismissSuggestionsTimer?.cancel();
          },
          onTap: () {
            selectPlace(place);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    place.source == HealthcarePlaceSource.saved
                        ? Icons.history_rounded
                        : placeIcon(place),
                    color: AppTheme.primaryColor,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text.rich(
                        highlightedName(place.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1E2A3A),
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        <String>[
                          categoryLabel(place),
                          if (place.country.isNotEmpty) place.country,
                          sourceLabel(place),
                        ].join(" • "),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 11.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (place.address.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          place.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF475467),
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (place.phone.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          place.phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 9),
                  child: Icon(
                    Icons.north_west_rounded,
                    size: 20,
                    color: Color(0xFF475467),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (phoneUri != null || directionsUri != null || websiteUri != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(65, 0, 10, 11),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                if (phoneUri != null)
                  placeActionButton(
                    icon: Icons.call_rounded,
                    label: tr("Call", "Gọi"),
                    onPressed: () {
                      unawaited(
                        openPlaceAction(
                          phoneUri,
                          unavailableEnglish:
                              "Calling is not available on this device.",
                          unavailableVietnamese:
                              "Thiết bị này không thể thực hiện cuộc gọi.",
                        ),
                      );
                    },
                  ),
                if (directionsUri != null)
                  placeActionButton(
                    icon: Icons.directions_rounded,
                    label: tr("Directions", "Chỉ đường"),
                    onPressed: () {
                      unawaited(
                        openPlaceAction(
                          directionsUri,
                          unavailableEnglish:
                              "Directions could not be opened right now.",
                          unavailableVietnamese: "Hiện không thể mở chỉ đường.",
                        ),
                      );
                    },
                  ),
                if (websiteUri != null)
                  placeActionButton(
                    icon: Icons.language_rounded,
                    label: tr("Website", "Trang web"),
                    onPressed: () {
                      unawaited(
                        openPlaceAction(
                          websiteUri,
                          unavailableEnglish:
                              "This website could not be opened right now.",
                          unavailableVietnamese:
                              "Hiện không thể mở trang web này.",
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget buildSuggestionList() {
    final suggestions = visibleSuggestions;

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.22),
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var index = 0; index < suggestions.length; index++) ...[
              buildSuggestionItem(suggestions[index]),
              if (index < suggestions.length - 1)
                Divider(
                  height: 1,
                  indent: 64,
                  color: AppTheme.primaryColor.withValues(alpha: 0.10),
                ),
            ],
            if (isSearching)
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 11, 15, 11),
                child: Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(
                          "Searching pharmacies, doctors, clinics, and hospitals...",
                          "Đang tìm nhà thuốc, bác sĩ, phòng khám và bệnh viện...",
                        ),
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!isSearching && searchMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
                child: Text(
                  searchMessage,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
              color: AppTheme.primaryColor.withValues(alpha: 0.05),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.map_outlined,
                    size: 17,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      tr(
                        "Tap a result to use it. Call, directions, and website buttons use its public Apple Maps information.",
                        "Chạm vào kết quả để chọn. Các nút gọi, chỉ đường và trang web dùng thông tin công khai từ Apple Maps.",
                      ),
                      style: const TextStyle(
                        color: Color(0xFF475467),
                        fontSize: 10.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
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

  @override
  Widget build(BuildContext context) {
    final shouldShowSuggestions =
        suggestionsOpen &&
        (widget.nameController.text.trim().isNotEmpty ||
            savedPlaces.isNotEmpty) &&
        (visibleSuggestions.isNotEmpty ||
            isSearching ||
            searchMessage.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: widget.nameController,
          focusNode: focusNode,
          maxLines: 1,
          textInputAction: TextInputAction.search,
          onChanged: handleQueryChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
            prefixIcon: Icon(
              Icons.local_hospital_rounded,
              color: AppTheme.primaryColor,
            ),
            suffixIcon: isSearching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search_rounded),
            filled: true,
            fillColor: widget.fillColor ?? Colors.white.withValues(alpha: 0.92),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(
                color: AppTheme.primaryColor.withValues(alpha: 0.18),
                width: 1.4,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          ),
        ),
        if (widget.showHelperText) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.public_rounded,
                  size: 16,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr(
                      "Type one name or category, such as CVS, clinic, hospital, or Kim. Add a city or ZIP to search another area.",
                      "Nhập một tên hoặc loại, như CVS, phòng khám, bệnh viện hoặc Kim. Thêm thành phố hay mã ZIP để tìm khu vực khác.",
                    ),
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (shouldShowSuggestions) ...[
          const SizedBox(height: 8),
          buildSuggestionList(),
        ],
      ],
    );
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    dismissSuggestionsTimer?.cancel();
    focusNode.removeListener(handleFocusChanged);
    focusNode.dispose();
    super.dispose();
  }
}
