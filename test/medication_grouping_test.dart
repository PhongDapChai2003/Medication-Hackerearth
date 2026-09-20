import 'package:flutter_application_1/medication.dart';
import 'package:flutter_application_1/medication_list_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("medications with the same provider address are grouped together", () {
    const first = Medication(
      id: "first",
      name: "Amoxicillin",
      dosage: "500 mg",
      instructions: "Take one capsule",
      pharmacyName: "CVS Pharmacy",
      pharmacyAddress: "123 Main Street, Anaheim, CA 92805",
      pharmacyPhone: "(714) 555-0100",
    );
    const second = Medication(
      id: "second",
      name: "Vitamin D",
      dosage: "1000 IU",
      instructions: "Take one tablet",
      pharmacyName: "CVS Pharmacy",
      pharmacyAddress: "  123 Main Street, Anaheim, CA 92805  ",
      pharmacyPhone: "(714) 555-0100",
    );
    const third = Medication(
      id: "third",
      name: "Cetirizine",
      dosage: "10 mg",
      instructions: "Take one tablet",
      pharmacyName: "Community Pharmacy",
      pharmacyAddress: "900 Harbor Boulevard, Anaheim, CA 92805",
    );

    final groups = groupMedicationsByAddress(<Medication>[
      first,
      second,
      third,
    ]);

    expect(groups, hasLength(2));
    expect(groups.first.medications, <Medication>[first, second]);
    expect(groups.first.phone, "(714) 555-0100");
    expect(groups.last.medications, <Medication>[third]);
  });

  test("same named provider groups even when its address is missing", () {
    const first = Medication(
      id: "first",
      name: "Medication A",
      dosage: "",
      instructions: "Take as directed",
      pharmacyName: "Dr. Kelvin Mai",
      pharmacyPhone: "(714) 332-1069",
    );
    const second = Medication(
      id: "second",
      name: "Medication B",
      dosage: "",
      instructions: "Take as directed",
      pharmacyName: "  DR. KELVIN MAI  ",
      pharmacyPhone: "714-332-1069",
    );

    final groups = groupMedicationsByAddress(<Medication>[first, second]);

    expect(groups, hasLength(1));
    expect(groups.single.medications, <Medication>[first, second]);
  });

  test("medications without any provider information remain visible", () {
    const first = Medication(
      id: "first",
      name: "Medication A",
      dosage: "",
      instructions: "Take as directed",
    );
    const second = Medication(
      id: "second",
      name: "Medication B",
      dosage: "",
      instructions: "Take as directed",
    );

    final groups = groupMedicationsByAddress(<Medication>[first, second]);

    expect(groups, hasLength(2));
    expect(groups.expand((group) => group.medications), <Medication>[
      first,
      second,
    ]);
  });

  test("provider address survives local and cloud JSON conversion", () {
    const medication = Medication(
      id: "address-test",
      name: "Medication",
      dosage: "10 mg",
      instructions: "Take as directed",
      pharmacyName: "CVS Pharmacy",
      pharmacyAddress: "123 Main Street, Anaheim, CA 92805",
      pharmacyPhone: "(714) 555-0100",
    );

    final restored = Medication.fromJson(medication.toJson());

    expect(restored.pharmacyAddress, medication.pharmacyAddress);
    expect(restored.pharmacyName, medication.pharmacyName);
    expect(restored.pharmacyPhone, medication.pharmacyPhone);
  });
}
