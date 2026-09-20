import 'package:flutter_application_1/healthcare_place_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("public phone number becomes a callable link", () {
    const place = HealthcarePlaceSuggestion(
      name: "CVS Pharmacy",
      phone: "(714) 555-0123",
    );

    expect(HealthcarePlaceService.phoneUri(place).toString(), "tel:7145550123");
  });

  test("coordinates are preferred for accurate directions", () {
    const place = HealthcarePlaceSuggestion(
      name: "Community Clinic",
      address: "123 Main Street",
      latitude: 33.789,
      longitude: -117.923,
    );

    final uri = HealthcarePlaceService.directionsUri(place);

    expect(uri?.host, "maps.apple.com");
    expect(uri?.queryParameters["daddr"], "33.789,-117.923");
    expect(uri?.queryParameters["q"], "Community Clinic");
  });

  test("a valid public website can be opened safely", () {
    const place = HealthcarePlaceSuggestion(
      name: "Community Hospital",
      website: "example.org/appointments",
    );

    expect(
      HealthcarePlaceService.websiteUri(place).toString(),
      "https://example.org/appointments",
    );
  });

  test("missing contact information does not create fake actions", () {
    const place = HealthcarePlaceSuggestion(name: "CVS Pharmacy");

    expect(HealthcarePlaceService.phoneUri(place), isNull);
    expect(HealthcarePlaceService.directionsUri(place), isNull);
    expect(HealthcarePlaceService.websiteUri(place), isNull);
  });
}
