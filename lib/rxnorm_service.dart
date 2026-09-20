import 'dart:convert';

import 'package:http/http.dart' as http;

class RxNormSuggestion {
  /// The complete name returned by RxNorm or shown by the on-device catalog.
  final String name;
  final String rxcui;
  final double score;
  final int rank;
  final String source;
  final String entryName;
  final String genericName;
  final String strength;
  final String doseForm;
  final bool isSavedMedication;

  const RxNormSuggestion({
    required this.name,
    required this.rxcui,
    required this.score,
    this.rank = 0,
    this.source = "RxNorm",
    this.entryName = "",
    this.genericName = "",
    this.strength = "",
    this.doseForm = "",
    this.isSavedMedication = false,
  });

  String get medicationName {
    final cleanEntryName = entryName.trim();
    return cleanEntryName.isEmpty ? name.trim() : cleanEntryName;
  }

  String detailText({required bool vietnamese}) {
    final details = <String>[];

    if (genericName.trim().isNotEmpty &&
        genericName.trim().toLowerCase() != medicationName.toLowerCase()) {
      details.add(
        vietnamese
            ? "Hoạt chất: ${genericName.trim()}"
            : "Generic: ${genericName.trim()}",
      );
    }

    if (strength.trim().isNotEmpty) {
      details.add(strength.trim());
    }

    if (doseForm.trim().isNotEmpty) {
      details.add(doseForm.trim());
    }

    if (isSavedMedication) {
      details.add(vietnamese ? "Đã lưu trước đây" : "Previously saved");
    } else if (source == "On device") {
      details.add(vietnamese ? "Gợi ý trên thiết bị" : "On-device suggestion");
    } else {
      details.add("RxNorm");
    }

    return details.join("  •  ");
  }
}

class RxNormService {
  static const int _maximumCachedQueries = 40;

  static final Map<String, List<RxNormSuggestion>> _queryCache =
      <String, List<RxNormSuggestion>>{};

  static const List<_MedicationCatalogEntry> _onDeviceCatalog = [
    _MedicationCatalogEntry("Acetaminophen", aliases: ["Tylenol"]),
    _MedicationCatalogEntry("Tylenol", genericName: "acetaminophen"),
    _MedicationCatalogEntry("Ibuprofen", aliases: ["Advil", "Motrin"]),
    _MedicationCatalogEntry("Advil", genericName: "ibuprofen"),
    _MedicationCatalogEntry("Motrin", genericName: "ibuprofen"),
    _MedicationCatalogEntry("Naproxen", aliases: ["Aleve"]),
    _MedicationCatalogEntry("Aleve", genericName: "naproxen"),
    _MedicationCatalogEntry("Aspirin"),
    _MedicationCatalogEntry("Amoxicillin"),
    _MedicationCatalogEntry(
      "Amoxicillin / Clavulanate",
      aliases: ["Augmentin"],
    ),
    _MedicationCatalogEntry(
      "Augmentin",
      genericName: "amoxicillin / clavulanate",
    ),
    _MedicationCatalogEntry("Azithromycin", aliases: ["Zithromax", "Z-Pak"]),
    _MedicationCatalogEntry("Cephalexin", aliases: ["Keflex"]),
    _MedicationCatalogEntry("Doxycycline"),
    _MedicationCatalogEntry("Metformin", aliases: ["Glucophage"]),
    _MedicationCatalogEntry("Lisinopril"),
    _MedicationCatalogEntry("Losartan"),
    _MedicationCatalogEntry("Amlodipine"),
    _MedicationCatalogEntry("Atorvastatin", aliases: ["Lipitor"]),
    _MedicationCatalogEntry("Rosuvastatin", aliases: ["Crestor"]),
    _MedicationCatalogEntry("Simvastatin", aliases: ["Zocor"]),
    _MedicationCatalogEntry("Levothyroxine", aliases: ["Synthroid"]),
    _MedicationCatalogEntry("Omeprazole", aliases: ["Prilosec"]),
    _MedicationCatalogEntry("Pantoprazole", aliases: ["Protonix"]),
    _MedicationCatalogEntry("Famotidine", aliases: ["Pepcid"]),
    _MedicationCatalogEntry("Albuterol", aliases: ["Ventolin", "ProAir"]),
    _MedicationCatalogEntry("Fluticasone", aliases: ["Flonase"]),
    _MedicationCatalogEntry("Cetirizine", aliases: ["Zyrtec"]),
    _MedicationCatalogEntry("Loratadine", aliases: ["Claritin"]),
    _MedicationCatalogEntry("Diphenhydramine", aliases: ["Benadryl"]),
    _MedicationCatalogEntry("Montelukast", aliases: ["Singulair"]),
    _MedicationCatalogEntry("Prednisone"),
    _MedicationCatalogEntry("Hydrocortisone"),
    _MedicationCatalogEntry("Gabapentin", aliases: ["Neurontin"]),
    _MedicationCatalogEntry("Sertraline", aliases: ["Zoloft"]),
    _MedicationCatalogEntry("Escitalopram", aliases: ["Lexapro"]),
    _MedicationCatalogEntry("Fluoxetine", aliases: ["Prozac"]),
    _MedicationCatalogEntry("Bupropion", aliases: ["Wellbutrin"]),
    _MedicationCatalogEntry("Trazodone"),
    _MedicationCatalogEntry("Duloxetine", aliases: ["Cymbalta"]),
    _MedicationCatalogEntry("Cyclobenzaprine", aliases: ["Flexeril"]),
    _MedicationCatalogEntry("Meloxicam", aliases: ["Mobic"]),
    _MedicationCatalogEntry("Tramadol"),
    _MedicationCatalogEntry("Tadalafil", aliases: ["Cialis"]),
    _MedicationCatalogEntry("Sildenafil", aliases: ["Viagra"]),
    _MedicationCatalogEntry("Tamsulosin", aliases: ["Flomax"]),
    _MedicationCatalogEntry("Finasteride", aliases: ["Proscar", "Propecia"]),
    _MedicationCatalogEntry("Docusate Sodium", aliases: ["Colace"]),
    _MedicationCatalogEntry("Polyethylene Glycol", aliases: ["MiraLAX"]),
    _MedicationCatalogEntry("Ondansetron", aliases: ["Zofran"]),
    _MedicationCatalogEntry(
      "Insulin Glargine",
      aliases: ["Lantus", "Basaglar"],
    ),
  ];

  static String correctLikelyOcrMedicationName(String value) {
    final cleanValue = value.trim().replaceAll(RegExp(r'\s+'), " ");
    final normalizedValue = _normalizeForSearch(cleanValue).replaceAll(" ", "");

    if (normalizedValue.length < 6 || RegExp(r'\d').hasMatch(normalizedValue)) {
      return cleanValue;
    }

    _OcrMedicationMatch? bestMatch;
    int secondBestDistance = 999;
    final comparedCandidates = <String>{};

    for (final entry in _onDeviceCatalog) {
      for (final candidate in <String>[entry.name, ...entry.aliases]) {
        final normalizedCandidate = _normalizeForSearch(
          candidate,
        ).replaceAll(" ", "");

        if (normalizedCandidate.length < 6 ||
            !comparedCandidates.add(normalizedCandidate) ||
            normalizedValue[0] != normalizedCandidate[0]) {
          continue;
        }

        final distance = _levenshteinDistance(
          normalizedValue,
          normalizedCandidate,
        );

        if (bestMatch == null || distance < bestMatch.distance) {
          secondBestDistance = bestMatch?.distance ?? secondBestDistance;
          bestMatch = _OcrMedicationMatch(
            correctedName: candidate,
            distance: distance,
          );
        } else if (distance < secondBestDistance) {
          secondBestDistance = distance;
        }
      }
    }

    if (bestMatch == null) {
      return cleanValue;
    }

    final allowedDistance = normalizedValue.length >= 11 ? 2 : 1;
    final isUniqueMatch = secondBestDistance >= bestMatch.distance + 2;

    if (bestMatch.distance > allowedDistance || !isUniqueMatch) {
      return cleanValue;
    }

    return bestMatch.correctedName;
  }

  static int _levenshteinDistance(String first, String second) {
    if (first == second) return 0;
    if (first.isEmpty) return second.length;
    if (second.isEmpty) return first.length;

    var previous = List<int>.generate(second.length + 1, (index) => index);

    for (int firstIndex = 1; firstIndex <= first.length; firstIndex++) {
      final current = List<int>.filled(second.length + 1, 0);
      current[0] = firstIndex;

      for (int secondIndex = 1; secondIndex <= second.length; secondIndex++) {
        final substitutionCost =
            first[firstIndex - 1] == second[secondIndex - 1] ? 0 : 1;
        final deletion = previous[secondIndex] + 1;
        final insertion = current[secondIndex - 1] + 1;
        final substitution = previous[secondIndex - 1] + substitutionCost;
        current[secondIndex] = <int>[deletion, insertion, substitution].reduce((
          firstValue,
          secondValue,
        ) {
          return firstValue < secondValue ? firstValue : secondValue;
        });
      }

      previous = current;
    }

    return previous.last;
  }

  static List<RxNormSuggestion> findOnDeviceSuggestions(
    String query, {
    Iterable<RxNormSuggestion> savedMedications = const [],
    int maximumResults = 8,
  }) {
    final normalizedQuery = _normalizeForSearch(query);

    if (normalizedQuery.isEmpty) {
      return [];
    }

    final ranked = <_RankedSuggestion>[];

    for (final saved in savedMedications) {
      final searchText = [
        saved.name,
        saved.entryName,
        saved.genericName,
        saved.strength,
        saved.doseForm,
      ].join(" ");
      final matchRank = _matchRank(searchText, normalizedQuery);

      if (matchRank == null) continue;

      ranked.add(
        _RankedSuggestion(
          suggestion: RxNormSuggestion(
            name: saved.name,
            rxcui: saved.rxcui,
            score: saved.score,
            rank: saved.rank,
            source: saved.source,
            entryName: saved.entryName,
            genericName: saved.genericName,
            strength: saved.strength,
            doseForm: saved.doseForm,
            isSavedMedication: true,
          ),
          matchRank: matchRank - 1,
        ),
      );
    }

    for (final catalogEntry in _onDeviceCatalog) {
      final searchText = [
        catalogEntry.name,
        catalogEntry.genericName,
        ...catalogEntry.aliases,
      ].join(" ");
      final matchRank = _matchRank(searchText, normalizedQuery);

      if (matchRank == null) continue;

      ranked.add(
        _RankedSuggestion(
          suggestion: RxNormSuggestion(
            name: catalogEntry.name,
            rxcui: "",
            score: 0,
            source: "On device",
            entryName: catalogEntry.name,
            genericName: catalogEntry.genericName,
          ),
          matchRank: matchRank,
        ),
      );
    }

    ranked.sort((first, second) {
      final rankComparison = first.matchRank.compareTo(second.matchRank);

      if (rankComparison != 0) return rankComparison;

      return first.suggestion.medicationName.toLowerCase().compareTo(
        second.suggestion.medicationName.toLowerCase(),
      );
    });

    return _deduplicateSuggestions(
      ranked.map((item) => item.suggestion),
      maximumResults: maximumResults,
    );
  }

  static Future<List<RxNormSuggestion>> findMedicationNames(
    String query, {
    int maximumResults = 12,
  }) async {
    final cleanQuery = query.trim();

    if (cleanQuery.length < 2) return [];

    final cacheKey = _normalizeForSearch(cleanQuery);
    final cached = _queryCache[cacheKey];

    if (cached != null) {
      return List<RxNormSuggestion>.from(cached);
    }

    final uri = Uri.https("rxnav.nlm.nih.gov", "/REST/approximateTerm.json", {
      "term": cleanQuery,
      "maxEntries": "20",
      "option": "1",
    });
    final response = await http
        .get(uri, headers: const {"Accept": "application/json"})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception("RxNorm returned ${response.statusCode}.");
    }

    final decoded = jsonDecode(response.body);
    final approximateGroup = decoded is Map
        ? decoded["approximateGroup"]
        : null;
    final candidates = approximateGroup is Map
        ? approximateGroup["candidate"]
        : null;

    if (candidates is! List) return [];

    final suggestions = <RxNormSuggestion>[];

    for (final candidate in candidates) {
      if (candidate is! Map) continue;

      final name = candidate["name"]?.toString().trim() ?? "";

      if (name.isEmpty) continue;

      suggestions.add(
        _buildRxNormSuggestion(
          fullName: name,
          query: cleanQuery,
          rxcui: candidate["rxcui"]?.toString().trim() ?? "",
          score: double.tryParse(candidate["score"]?.toString() ?? "") ?? 0,
          rank: int.tryParse(candidate["rank"]?.toString() ?? "") ?? 0,
          source: candidate["source"]?.toString().trim() ?? "RxNorm",
        ),
      );
    }

    suggestions.sort((first, second) {
      final rankComparison = first.rank.compareTo(second.rank);

      if (rankComparison != 0) return rankComparison;

      return second.score.compareTo(first.score);
    });

    final result = _deduplicateSuggestions(
      suggestions,
      maximumResults: maximumResults,
    );

    if (_queryCache.length >= _maximumCachedQueries) {
      _queryCache.remove(_queryCache.keys.first);
    }

    _queryCache[cacheKey] = List<RxNormSuggestion>.from(result);
    return result;
  }

  static RxNormSuggestion _buildRxNormSuggestion({
    required String fullName,
    required String query,
    required String rxcui,
    required double score,
    required int rank,
    required String source,
  }) {
    final brandName = _extractBrandName(fullName);
    final genericName = _extractGenericName(fullName);
    final normalizedQuery = _normalizeForSearch(query);
    final normalizedBrand = _normalizeForSearch(brandName);
    final queryMatchesBrand =
        brandName.isNotEmpty &&
        normalizedQuery.length >= 2 &&
        (normalizedBrand.contains(normalizedQuery) ||
            normalizedQuery.contains(normalizedBrand));
    final entryName = queryMatchesBrand
        ? brandName
        : genericName.isNotEmpty
        ? genericName
        : fullName;

    return RxNormSuggestion(
      name: fullName,
      rxcui: rxcui,
      score: score,
      rank: rank,
      source: source.isEmpty ? "RxNorm" : source,
      entryName: _titleCaseMedicationName(entryName),
      genericName: genericName,
      strength: _extractStrength(fullName),
      doseForm: _extractDoseForm(fullName),
    );
  }

  static List<RxNormSuggestion> _deduplicateSuggestions(
    Iterable<RxNormSuggestion> suggestions, {
    required int maximumResults,
  }) {
    final result = <RxNormSuggestion>[];
    final seen = <String>{};

    for (final suggestion in suggestions) {
      final key = _normalizeForSearch(
        [suggestion.name, suggestion.strength, suggestion.doseForm].join(" "),
      );

      if (key.isEmpty || !seen.add(key)) continue;

      result.add(suggestion);

      if (result.length >= maximumResults) {
        break;
      }
    }

    return result;
  }

  static int? _matchRank(String value, String normalizedQuery) {
    final normalizedValue = _normalizeForSearch(value);

    if (normalizedValue == normalizedQuery) return 0;
    if (normalizedValue.startsWith(normalizedQuery)) return 1;

    final words = normalizedValue.split(" ");

    if (words.any((word) => word.startsWith(normalizedQuery))) {
      return 2;
    }

    if (normalizedValue.contains(normalizedQuery)) return 3;
    return null;
  }

  static String _extractBrandName(String value) {
    final matches = RegExp(r'\[([^\]]+)\]').allMatches(value);

    if (matches.isEmpty) return "";
    return matches.last.group(1)?.trim() ?? "";
  }

  static String _extractStrength(String value) {
    final strengthPattern = RegExp(
      r'\b\d+(?:\.\d+)?\s*(?:MG|MCG|G|GRAM|ML|L|UNIT|UNITS|UNT|MEQ|MMOL|%)'
      r'(?:\s*/\s*(?:ML|L|ACTUATION|DOSE|HR|HOUR))?',
      caseSensitive: false,
    );
    final matches = strengthPattern
        .allMatches(value)
        .map((match) => match.group(0)?.trim() ?? "")
        .where((item) => item.isNotEmpty)
        .toList();

    if (matches.isEmpty) return "";
    return matches.take(3).join(" / ");
  }

  static String _extractDoseForm(String value) {
    const doseForms = [
      "Delayed Release Oral Capsule",
      "Delayed Release Oral Tablet",
      "Extended Release Oral Capsule",
      "Extended Release Oral Tablet",
      "Disintegrating Oral Tablet",
      "Chewable Oral Tablet",
      "Metered Dose Inhaler",
      "Prefilled Syringe",
      "Oral Suspension",
      "Oral Solution",
      "Oral Capsule",
      "Oral Tablet",
      "Chewable Tablet",
      "Sublingual Tablet",
      "Buccal Tablet",
      "Topical Cream",
      "Topical Ointment",
      "Topical Lotion",
      "Transdermal Patch",
      "Nasal Spray",
      "Ophthalmic Solution",
      "Otic Solution",
      "Rectal Suppository",
      "Vaginal Suppository",
      "Inhalation Solution",
      "Injectable Solution",
      "Injection",
      "Capsule",
      "Tablet",
      "Suspension",
      "Solution",
      "Cream",
      "Ointment",
      "Lotion",
      "Patch",
      "Spray",
      "Powder",
      "Suppository",
      "Drops",
      "Pill",
    ];

    final lowerValue = value.toLowerCase();

    for (final doseForm in doseForms) {
      if (lowerValue.contains(doseForm.toLowerCase())) {
        return doseForm;
      }
    }

    return "";
  }

  static String _extractGenericName(String value) {
    var result = value.replaceAll(RegExp(r'\[[^\]]+\]'), " ");
    result = result.replaceAll(
      RegExp(
        r'\b\d+(?:\.\d+)?\s*(?:MG|MCG|G|GRAM|ML|L|UNIT|UNITS|UNT|MEQ|MMOL|%)'
        r'(?:\s*/\s*(?:ML|L|ACTUATION|DOSE|HR|HOUR))?',
        caseSensitive: false,
      ),
      " ",
    );

    const removablePhrases = [
      "Delayed Release Oral Capsule",
      "Delayed Release Oral Tablet",
      "Extended Release Oral Capsule",
      "Extended Release Oral Tablet",
      "Disintegrating Oral Tablet",
      "Chewable Oral Tablet",
      "Metered Dose Inhaler",
      "Prefilled Syringe",
      "Oral Suspension",
      "Oral Solution",
      "Oral Capsule",
      "Oral Tablet",
      "Chewable Tablet",
      "Sublingual Tablet",
      "Buccal Tablet",
      "Topical Cream",
      "Topical Ointment",
      "Topical Lotion",
      "Transdermal Patch",
      "Nasal Spray",
      "Ophthalmic Solution",
      "Otic Solution",
      "Rectal Suppository",
      "Vaginal Suppository",
      "Inhalation Solution",
      "Injectable Solution",
      "Injection",
      "Capsule",
      "Tablet",
      "Suspension",
      "Solution",
      "Cream",
      "Ointment",
      "Lotion",
      "Patch",
      "Spray",
      "Powder",
      "Suppository",
      "Drops",
      "Pill",
      "Oral Product",
      "Chewable Product",
      "Product",
    ];

    for (final phrase in removablePhrases) {
      result = result.replaceAll(
        RegExp(RegExp.escape(phrase), caseSensitive: false),
        " ",
      );
    }

    result = result
        .replaceAll(RegExp(r'\b\d+\s*(?:HR|HOUR)\b', caseSensitive: false), " ")
        .replaceAll(RegExp(r'\s*/\s*'), " / ")
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();

    return _titleCaseMedicationName(result);
  }

  static String _titleCaseMedicationName(String value) {
    final cleanValue = value.trim().replaceAll(RegExp(r'\s+'), " ");

    if (cleanValue.isEmpty) return "";

    return cleanValue
        .split(" ")
        .map((word) {
          if (word == "/") return word;
          if (word.length <= 1) return word.toUpperCase();

          final lowerWord = word.toLowerCase();
          return "${lowerWord[0].toUpperCase()}${lowerWord.substring(1)}";
        })
        .join(" ");
  }

  static String _normalizeForSearch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), " ")
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();
  }
}

class _MedicationCatalogEntry {
  final String name;
  final String genericName;
  final List<String> aliases;

  const _MedicationCatalogEntry(
    this.name, {
    this.genericName = "",
    this.aliases = const [],
  });
}

class _RankedSuggestion {
  final RxNormSuggestion suggestion;
  final int matchRank;

  const _RankedSuggestion({required this.suggestion, required this.matchRank});
}

class _OcrMedicationMatch {
  final String correctedName;
  final int distance;

  const _OcrMedicationMatch({
    required this.correctedName,
    required this.distance,
  });
}
