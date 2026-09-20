import Flutter
import MapKit
import UIKit
import UserNotifications
import Vision
import WatchConnectivity
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  WCSessionDelegate
{
  private var healthcarePlaceChannel: FlutterMethodChannel?
  private var prescriptionOcrChannel: FlutterMethodChannel?
  private var appleWatchChannel: FlutterMethodChannel?
  private var watchSession: WCSession?
  private var activeHealthcareSearches = [MKLocalSearch]()
  private var activeHealthcareResult: FlutterResult?
  private var healthcareSearchGeneration = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "medication_reminder/healthcare_places",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "searchHealthcarePlaces" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let arguments = call.arguments as? [String: Any],
        let query = arguments["query"] as? String
      else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "A place-search query is required.",
            details: nil
          )
        )
        return
      }

      let requestedLimit = (arguments["limit"] as? Int) ?? 12
      self?.searchHealthcarePlaces(
        query: query,
        limit: min(max(requestedLimit, 1), 20),
        result: result
      )
    }

    healthcarePlaceChannel = channel

    let ocrChannel = FlutterMethodChannel(
      name: "medication_reminder/macos_vision_ocr",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    ocrChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "recognizePrescriptionImages" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let arguments = call.arguments as? [String: Any],
        let paths = arguments["paths"] as? [String],
        !paths.isEmpty
      else {
        result(
          FlutterError(
            code: "INVALID_OCR_ARGUMENTS",
            message: "At least one prescription image path is required.",
            details: nil
          )
        )
        return
      }

      guard let self else {
        result(
          FlutterError(
            code: "OCR_UNAVAILABLE",
            message: "The iPhone OCR service is unavailable.",
            details: nil
          )
        )
        return
      }

      self.recognizePrescriptionImages(paths: paths, result: result)
    }

    prescriptionOcrChannel = ocrChannel

    let watchChannel = FlutterMethodChannel(
      name: "medication_reminder/apple_watch",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    if WCSession.isSupported() {
      let session = WCSession.default
      session.delegate = self
      session.activate()
      watchSession = session
    }

    watchChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "WATCH_UNAVAILABLE", message: nil, details: nil))
        return
      }

      switch call.method {
      case "watchStatus":
        result(self.appleWatchStatus())
      case "syncMedicationSummary":
        guard
          let session = self.watchSession,
          session.activationState == .activated,
          session.isPaired,
          session.isWatchAppInstalled,
          let context = call.arguments as? [String: Any]
        else {
          result(false)
          return
        }

        do {
          try session.updateApplicationContext(context)
          result(true)
        } catch {
          result(
            FlutterError(
              code: "WATCH_SYNC_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    appleWatchChannel = watchChannel
  }

  private func appleWatchStatus() -> [String: Any] {
    guard WCSession.isSupported(), let session = watchSession else {
      return [
        "supported": false,
        "paired": false,
        "watchAppInstalled": false,
        "reachable": false,
      ]
    }

    return [
      "supported": true,
      "paired": session.isPaired,
      "watchAppInstalled": session.isWatchAppInstalled,
      "reachable": session.isReachable,
    ]
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {}

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  private func recognizePrescriptionImages(
    paths: [String],
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "OCR_UNAVAILABLE",
              message: "The iPhone OCR service stopped before recognition completed.",
              details: nil
            )
          )
        }
        return
      }

      let recognizedImages = paths.map {
        self.recognizePrescriptionImage(atPath: $0)
      }

      DispatchQueue.main.async {
        result(recognizedImages)
      }
    }
  }

  private func recognizePrescriptionImage(
    atPath path: String
  ) -> [String: Any] {
    let fileUrl = URL(fileURLWithPath: path)

    guard FileManager.default.fileExists(atPath: fileUrl.path) else {
      return [
        "path": path,
        "text": "",
        "lineCount": 0,
        "lowConfidenceLineCount": 0,
        "error": "The selected image could not be found.",
      ]
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0
    request.customWords = [
      "Rosuvastatin", "Atorvastatin", "Simvastatin", "Lisinopril",
      "Losartan", "Amlodipine", "Metformin", "Amoxicillin",
      "Azithromycin", "Cephalexin", "Doxycycline", "Levothyroxine",
      "Omeprazole", "Pantoprazole", "Gabapentin", "Hydrocortisone",
      "Acetaminophen", "Ibuprofen", "Tamsulosin", "Finasteride",
      "Uống", "viên", "mỗi", "ngày", "sáng", "trưa", "chiều", "tối",
      "trước", "sau", "ăn", "khi cần", "Qty", "Refill",
    ]

    if #available(iOS 16.0, *) {
      request.automaticallyDetectsLanguage = true
    }

    if let supportedLanguages = try? request.supportedRecognitionLanguages() {
      let preferredLanguages = ["en-US", "vi-VN"].filter {
        supportedLanguages.contains($0)
      }

      if !preferredLanguages.isEmpty {
        request.recognitionLanguages = preferredLanguages
      }
    } else {
      request.recognitionLanguages = ["en-US"]
    }

    do {
      let handler = VNImageRequestHandler(url: fileUrl, options: [:])
      try handler.perform([request])
    } catch {
      return [
        "path": path,
        "text": "",
        "lineCount": 0,
        "lowConfidenceLineCount": 0,
        "error": error.localizedDescription,
      ]
    }

    let observations = (request.results ?? []).sorted {
      firstObservation,
      secondObservation in
      let verticalDifference = abs(
        firstObservation.boundingBox.midY -
          secondObservation.boundingBox.midY
      )

      if verticalDifference > 0.015 {
        return firstObservation.boundingBox.maxY >
          secondObservation.boundingBox.maxY
      }

      return firstObservation.boundingBox.minX <
        secondObservation.boundingBox.minX
    }

    var recognizedLines = [String]()
    var lowConfidenceLineCount = 0

    for observation in observations {
      guard let candidate = observation.topCandidates(1).first else {
        continue
      }

      let line = candidate.string
        .replacingOccurrences(
          of: #"[ \t]+"#,
          with: " ",
          options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

      guard !line.isEmpty else {
        continue
      }

      recognizedLines.append(line)

      if candidate.confidence < 0.65 {
        lowConfidenceLineCount += 1
      }
    }

    return [
      "path": path,
      "text": recognizedLines.joined(separator: "\n"),
      "lineCount": recognizedLines.count,
      "lowConfidenceLineCount": lowConfidenceLineCount,
      "error": "",
    ]
  }

  private func searchHealthcarePlaces(
    query: String,
    limit: Int,
    result: @escaping FlutterResult
  ) {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

    guard cleanQuery.count >= 2 else {
      result([])
      return
    }

    cancelActiveHealthcareWork()
    performHealthcareSearch(
      query: cleanQuery,
      limit: limit,
      result: result
    )
  }

  private func performHealthcareSearch(
    query: String,
    limit: Int,
    result: @escaping FlutterResult
  ) {
    activeHealthcareResult = result
    let generation = healthcareSearchGeneration
    runHealthcareSearches(
      queries: expandedHealthcareQueries(query: query),
      originalQuery: query,
      limit: limit,
      generation: generation,
      result: result
    )
  }

  private func expandedHealthcareQueries(query: String) -> [String] {
    let normalizedQuery = normalizedSearchText(query)
    let specificTokens = specificQueryTokens(normalizedQuery)
    var queries = [query]

    if !specificTokens.isEmpty {
      queries.append("\(query) pharmacy")
      queries.append("\(query) clinic")
      queries.append("\(query) hospital")
    }

    var seen = Set<String>()
    return queries.filter {
      let key = normalizedSearchText($0)
      return !key.isEmpty && seen.insert(key).inserted
    }
  }

  private func runHealthcareSearches(
    queries: [String],
    originalQuery: String,
    limit: Int,
    generation: Int,
    result: @escaping FlutterResult
  ) {
    let group = DispatchGroup()
    var collectedMapItems = [MKMapItem]()
    var firstError: Error?

    for query in queries {
      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = query
      request.resultTypes = .pointOfInterest

      let search = MKLocalSearch(request: request)
      activeHealthcareSearches.append(search)
      group.enter()

      search.start { response, error in
        DispatchQueue.main.async {
          if generation == self.healthcareSearchGeneration {
            if let mapItems = response?.mapItems {
              collectedMapItems.append(contentsOf: mapItems)
            }

            if firstError == nil {
              firstError = error
            }
          }

          group.leave()
        }
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard
        let self,
        generation == self.healthcareSearchGeneration
      else {
        return
      }

      self.activeHealthcareSearches = []
      self.activeHealthcareResult = nil

      if collectedMapItems.isEmpty, let firstError {
        result(
          FlutterError(
            code: "PLACE_SEARCH_FAILED",
            message: firstError.localizedDescription,
            details: nil
          )
        )
        return
      }

      result(
        self.healthcarePlaces(
          from: collectedMapItems,
          query: originalQuery,
          limit: limit
        )
      )
    }
  }

  private func healthcarePlaces(
    from mapItems: [MKMapItem],
    query: String,
    limit: Int
  ) -> [[String: Any]] {
    let candidates = mapItems.compactMap { mapItem
      -> (mapItem: MKMapItem, category: String, score: Int)? in
      guard
        let category = healthcareCategory(for: mapItem),
        isRelevantHealthcareResult(mapItem, query: query)
      else {
        return nil
      }

      let score = healthcareRelevanceScore(
        for: mapItem,
        category: category,
        query: query
      )

      return (mapItem: mapItem, category: category, score: score)
    }
    .sorted { first, second in
      if first.score != second.score {
        return first.score > second.score
      }

      return (first.mapItem.name ?? "") < (second.mapItem.name ?? "")
    }

    var seen = Set<String>()
    var places = [[String: Any]]()

    for candidate in candidates {
      let mapItem = candidate.mapItem
      let name = mapItem.name?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ) ?? ""

      if name.isEmpty {
        continue
      }

      let address = displayAddress(for: mapItem)
      let coordinate = mapItem.placemark.coordinate
      let key = "\(name.lowercased())|\(address.lowercased())"

      if !seen.insert(key).inserted {
        continue
      }

      places.append([
        "name": name,
        "address": address,
        "phone": mapItem.phoneNumber ?? "",
        "website": mapItem.url?.absoluteString ?? "",
        "category": candidate.category,
        "country": mapItem.placemark.country ?? "",
        "latitude": coordinate.latitude,
        "longitude": coordinate.longitude,
      ])

      if places.count >= limit {
        break
      }
    }

    return places
  }

  private func isRelevantHealthcareResult(
    _ mapItem: MKMapItem,
    query: String
  ) -> Bool {
    let tokens = specificQueryTokens(normalizedSearchText(query))

    if tokens.isEmpty {
      return true
    }

    let searchable = normalizedSearchText(
      "\(mapItem.name ?? "") \(mapItem.placemark.title ?? "")"
    )
    let words = searchable.split(separator: " ").map(String.init)

    return tokens.allSatisfy { token in
      searchable.contains(token) ||
        words.contains(where: { $0.hasPrefix(token) })
    }
  }

  private func cancelActiveHealthcareWork() {
    healthcareSearchGeneration += 1

    for search in activeHealthcareSearches {
      search.cancel()
    }

    activeHealthcareSearches = []

    if let activeHealthcareResult {
      activeHealthcareResult([])
      self.activeHealthcareResult = nil
    }
  }

  private func displayAddress(for mapItem: MKMapItem) -> String {
    let name = mapItem.name?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ) ?? ""
    var address = mapItem.placemark.title?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ) ?? ""

    let namePrefix = "\(name), "

    if !name.isEmpty &&
        address.lowercased().hasPrefix(namePrefix.lowercased()) {
      address.removeFirst(namePrefix.count)
    }

    return address
  }

  private func healthcareCategory(
    for mapItem: MKMapItem
  ) -> String? {
    switch mapItem.pointOfInterestCategory {
    case .pharmacy:
      return "pharmacy"
    case .hospital:
      return "hospital"
    default:
      break
    }

    let searchable = [
      mapItem.name ?? "",
      mapItem.placemark.title ?? "",
    ]
      .joined(separator: " ")
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: .current
      )
      .lowercased()

    if searchable.contains("pharmacy") ||
        searchable.contains("drugstore") ||
        searchable.contains("chemist") ||
        searchable.contains("apothecary") ||
        searchable.contains("farmacia") ||
        searchable.contains("pharmacie") ||
        searchable.contains("apotheek") ||
        searchable.contains("apotek") ||
        searchable.contains("eczane") ||
        searchable.contains("nha thuoc") ||
        searchable.contains("약국") ||
        searchable.contains("薬局") ||
        searchable.contains("药房") {
      return "pharmacy"
    }

    if searchable.contains("hospital") ||
        searchable.contains("medical center") ||
        searchable.contains("medical centre") ||
        searchable.contains("benh vien") ||
        searchable.contains("hopital") ||
        searchable.contains("krankenhaus") ||
        searchable.contains("ospedale") {
      return "hospital"
    }

    if searchable.contains("clinic") ||
        searchable.contains("medical center") ||
        searchable.contains("health center") ||
        searchable.contains("health centre") ||
        searchable.contains("medical group") ||
        searchable.contains("family medicine") ||
        searchable.contains("primary care") ||
        searchable.contains("pediatric") ||
        searchable.contains("dermatology") ||
        searchable.contains("cardiology") ||
        searchable.contains("orthopedic") ||
        searchable.contains("urgent care") ||
        searchable.contains("phong kham") {
      return "clinic"
    }

    if searchable.contains("doctor") ||
        searchable.contains("physician") ||
        searchable.contains("dr ") ||
        searchable.contains("dr.") ||
        searchable.contains(", md") ||
        searchable.contains(" md ") ||
        searchable.contains(", do") ||
        searchable.contains(" d.o.") ||
        searchable.contains("bac si") {
      return "doctor"
    }

    return nil
  }

  private func healthcareRelevanceScore(
    for mapItem: MKMapItem,
    category: String,
    query: String
  ) -> Int {
    let normalizedQuery = normalizedSearchText(query)
    let normalizedName = normalizedSearchText(mapItem.name ?? "")
    let normalizedAddress = normalizedSearchText(
      mapItem.placemark.title ?? ""
    )
    let searchable = "\(normalizedName) \(normalizedAddress)"
    var score = 0

    if normalizedName == normalizedQuery {
      score += 2_500
    } else if normalizedName.hasPrefix(normalizedQuery) {
      score += 1_800
    } else if normalizedName.contains(normalizedQuery) {
      score += 1_400
    }

    for token in specificQueryTokens(normalizedQuery) {
      let nameWords = normalizedName.split(separator: " ").map(String.init)

      if nameWords.contains(token) {
        score += 600
      } else if nameWords.contains(where: { $0.hasPrefix(token) }) {
        score += 450
      } else if normalizedName.contains(token) {
        score += 300
      } else if searchable.contains(token) {
        score += 160
      } else {
        score -= 120
      }
    }

    if queryRequestsPharmacy(normalizedQuery) && category == "pharmacy" {
      score += 500
    }

    if queryRequestsHospital(normalizedQuery) && category == "hospital" {
      score += 500
    }

    return score
  }

  private func normalizedSearchText(_ value: String) -> String {
    let folded = value
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: .current
      )
      .lowercased()
    let pieces = folded.components(
      separatedBy: CharacterSet.alphanumerics.inverted
    )
    return pieces.filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func specificQueryTokens(_ normalizedQuery: String) -> [String] {
    let genericTerms = [
      "pharmacy", "pharmacies", "drugstore", "chemist", "hospital",
      "hospitals", "clinic", "clinics", "doctor", "doctors", "medical",
      "center", "centre", "health", "care", "near", "nearby", "me",
      "nha", "thuoc", "benh", "vien", "phong", "kham",
    ]

    return normalizedQuery.split(separator: " ").map(String.init).filter {
      token in
      guard token.count >= 3 else {
        return false
      }

      return !genericTerms.contains {
        genericTerm in genericTerm.hasPrefix(token)
      }
    }
  }

  private func queryRequestsPharmacy(_ normalizedQuery: String) -> Bool {
    return normalizedQuery.contains("pharm") ||
      normalizedQuery.contains("drugstore") ||
      normalizedQuery.contains("chemist") ||
      normalizedQuery.contains("nha thuoc") ||
      normalizedQuery.contains("cvs") ||
      normalizedQuery.contains("walgreens")
  }

  private func queryRequestsHospital(_ normalizedQuery: String) -> Bool {
    return normalizedQuery.contains("hospital") ||
      normalizedQuery.contains("medical center") ||
      normalizedQuery.contains("medical centre") ||
      normalizedQuery.contains("benh vien")
  }

}
