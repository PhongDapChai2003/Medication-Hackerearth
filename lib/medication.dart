class Medication {
  final String id;
  final String name;
  final String dosage;
  final String quantity;
  final String remainingQuantity;
  final String inventoryBaselineQuantity;
  final String inventoryBaselineAt;
  final String instructions;
  final String notes;
  final String pharmacyName;
  final String pharmacyAddress;
  final String pharmacyPhone;
  final List<String> reminderTimes;
  final String doseStatus;
  final String doseStatusDate;
  final Map<String, String> doseRecords;
  final Map<String, String> doseRecordUpdatedAt;
  final Map<String, String> deletedDoseRecords;
  final String startDate;
  final String endDate;
  final int pillBoxSlot;
  final String updatedAt;

  const Medication({
    this.id = "",
    required this.name,
    required this.dosage,
    this.quantity = "",
    this.remainingQuantity = "",
    this.inventoryBaselineQuantity = "",
    this.inventoryBaselineAt = "",
    required this.instructions,
    this.notes = "",
    this.pharmacyName = "",
    this.pharmacyAddress = "",
    this.pharmacyPhone = "",
    this.reminderTimes = const [],
    this.doseStatus = "notTakenYet",
    this.doseStatusDate = "",
    this.doseRecords = const {},
    this.doseRecordUpdatedAt = const {},
    this.deletedDoseRecords = const {},
    this.startDate = "",
    this.endDate = "",
    this.pillBoxSlot = -1,
    this.updatedAt = "",
  });

  Medication copyWith({
    String? id,
    String? name,
    String? dosage,
    String? quantity,
    String? remainingQuantity,
    String? inventoryBaselineQuantity,
    String? inventoryBaselineAt,
    String? instructions,
    String? notes,
    String? pharmacyName,
    String? pharmacyAddress,
    String? pharmacyPhone,
    List<String>? reminderTimes,
    String? doseStatus,
    String? doseStatusDate,
    Map<String, String>? doseRecords,
    Map<String, String>? doseRecordUpdatedAt,
    Map<String, String>? deletedDoseRecords,
    String? startDate,
    String? endDate,
    int? pillBoxSlot,
    String? updatedAt,
  }) {
    return Medication(
      id: id ?? this.id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      quantity: quantity ?? this.quantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      inventoryBaselineQuantity:
          inventoryBaselineQuantity ?? this.inventoryBaselineQuantity,
      inventoryBaselineAt: inventoryBaselineAt ?? this.inventoryBaselineAt,
      instructions: instructions ?? this.instructions,
      notes: notes ?? this.notes,
      pharmacyName: pharmacyName ?? this.pharmacyName,
      pharmacyAddress: pharmacyAddress ?? this.pharmacyAddress,
      pharmacyPhone: pharmacyPhone ?? this.pharmacyPhone,
      reminderTimes: reminderTimes ?? this.reminderTimes,
      doseStatus: doseStatus ?? this.doseStatus,
      doseStatusDate: doseStatusDate ?? this.doseStatusDate,
      doseRecords: doseRecords ?? this.doseRecords,
      doseRecordUpdatedAt: doseRecordUpdatedAt ?? this.doseRecordUpdatedAt,
      deletedDoseRecords: deletedDoseRecords ?? this.deletedDoseRecords,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      pillBoxSlot: pillBoxSlot ?? this.pillBoxSlot,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "name": name,
      "dosage": dosage,
      "quantity": quantity,
      "remainingQuantity": remainingQuantity,
      "inventoryBaselineQuantity": inventoryBaselineQuantity,
      "inventoryBaselineAt": inventoryBaselineAt,
      "instructions": instructions,
      "notes": notes,
      "pharmacyName": pharmacyName,
      "pharmacyAddress": pharmacyAddress,
      "pharmacyPhone": pharmacyPhone,
      "reminderTimes": reminderTimes,
      "doseStatus": doseStatus,
      "doseStatusDate": doseStatusDate,
      "doseRecords": doseRecords,
      "doseRecordUpdatedAt": doseRecordUpdatedAt,
      "deletedDoseRecords": deletedDoseRecords,
      "startDate": startDate,
      "endDate": endDate,
      "pillBoxSlot": pillBoxSlot,
      "updatedAt": updatedAt,
    };
  }

  factory Medication.fromJson(Map<String, dynamic> json) {
    final String quantity = _readString(json["quantity"]);
    final String remainingQuantity = _readString(
      json["remainingQuantity"],
      fallback: quantity,
    );

    return Medication(
      id: _readString(json["id"]),
      name: _readString(json["name"]),
      dosage: _readString(json["dosage"]),
      quantity: quantity,
      remainingQuantity: remainingQuantity,
      inventoryBaselineQuantity: _readString(
        json["inventoryBaselineQuantity"],
        fallback: remainingQuantity,
      ),
      inventoryBaselineAt: _readString(json["inventoryBaselineAt"]),
      instructions: _readString(json["instructions"]),
      notes: _readString(json["notes"]),
      pharmacyName: _readString(json["pharmacyName"]),
      pharmacyAddress: _readString(json["pharmacyAddress"]),
      pharmacyPhone: _readString(json["pharmacyPhone"]),
      reminderTimes: _readStringList(json["reminderTimes"]),
      doseStatus: _readString(json["doseStatus"], fallback: "notTakenYet"),
      doseStatusDate: _readString(json["doseStatusDate"]),
      doseRecords: _readStringMap(json["doseRecords"]),
      doseRecordUpdatedAt: _readStringMap(json["doseRecordUpdatedAt"]),
      deletedDoseRecords: _readStringMap(json["deletedDoseRecords"]),
      startDate: _readString(json["startDate"]),
      endDate: _readString(json["endDate"]),
      pillBoxSlot: _readPillBoxSlot(json["pillBoxSlot"]),
      updatedAt: _readString(json["updatedAt"]),
    );
  }

  static String _readString(dynamic value, {String fallback = ""}) {
    if (value == null) {
      return fallback;
    }

    return value.toString();
  }

  static List<String> _readStringList(dynamic value) {
    if (value == null) {
      return [];
    }

    if (value is List) {
      return value.map((item) {
        return item.toString();
      }).toList();
    }

    return [];
  }

  static int _readPillBoxSlot(dynamic value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? "");
    return parsed != null && parsed >= 0 && parsed < 10 ? parsed : -1;
  }

  static Map<String, String> _readStringMap(dynamic value) {
    if (value == null) {
      return {};
    }

    if (value is Map) {
      final Map<String, String> cleanMap = {};

      value.forEach((key, mapValue) {
        cleanMap[key.toString()] = mapValue.toString();
      });

      return cleanMap;
    }

    return {};
  }
}
