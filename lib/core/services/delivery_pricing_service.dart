import 'dart:math' as math;

class DeliveryLandmark {
  final String name;
  final double latitude;
  final double longitude;
  final double baseFee;
  final double distanceFromCenterKm;

  const DeliveryLandmark({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.baseFee,
    required this.distanceFromCenterKm,
  });
}

class DeliveryPricingResult {
  final double feeAmount;
  final int feeCents;
  final double distanceFromCenterKm;
  final String primaryAreaName;
  final String? secondaryAreaName;
  final double distanceToPrimaryKm;

  const DeliveryPricingResult({
    required this.feeAmount,
    required this.feeCents,
    required this.distanceFromCenterKm,
    required this.primaryAreaName,
    this.secondaryAreaName,
    required this.distanceToPrimaryKm,
  });

  String get summaryLabel {
    if (secondaryAreaName != null && secondaryAreaName != primaryAreaName) {
      return '$primaryAreaName / $secondaryAreaName area';
    }
    return '$primaryAreaName area';
  }
}

class DeliveryPricingService {
  // Maseru Town (City Centre) Reference Point
  static const double centerLat = -29.3101;
  static const double centerLng = 27.4782;

  static const List<DeliveryLandmark> landmarks = [
    // --- M40 Zone ---
    DeliveryLandmark(
      name: 'Ha Hoohlo',
      latitude: -29.3035,
      longitude: 27.4667,
      baseFee: 40.0,
      distanceFromCenterKm: 2.8,
    ),
    DeliveryLandmark(
      name: 'Maseru West',
      latitude: -29.3115,
      longitude: 27.4645,
      baseFee: 40.0,
      distanceFromCenterKm: 2.1,
    ),
    DeliveryLandmark(
      name: 'Moshoeshoe 2',
      latitude: -29.3021,
      longitude: 27.4853,
      baseFee: 40.0,
      distanceFromCenterKm: 2.3,
    ),
    DeliveryLandmark(
      name: 'Stationeng (Maseru Station)',
      latitude: -29.3215,
      longitude: 27.4730,
      baseFee: 40.0,
      distanceFromCenterKm: 5.0,
    ),
    DeliveryLandmark(
      name: 'Thabong',
      latitude: -29.3150,
      longitude: 27.5250,
      baseFee: 40.0,
      distanceFromCenterKm: 7.0,
    ),

    // --- M50 Zone ---
    DeliveryLandmark(
      name: 'Ha Mabote',
      latitude: -29.2900,
      longitude: 27.5200,
      baseFee: 50.0,
      distanceFromCenterKm: 6.7,
    ),
    DeliveryLandmark(
      name: 'Ha Tsosane',
      latitude: -29.3020,
      longitude: 27.5140,
      baseFee: 50.0,
      distanceFromCenterKm: 6.1,
    ),
    DeliveryLandmark(
      name: 'Khubetsoana',
      latitude: -29.2811,
      longitude: 27.5352,
      baseFee: 50.0,
      distanceFromCenterKm: 7.0,
    ),
    DeliveryLandmark(
      name: 'Ha Pita',
      latitude: -29.3582,
      longitude: 27.5021,
      baseFee: 50.0,
      distanceFromCenterKm: 8.8,
    ),
    DeliveryLandmark(
      name: 'Ha Thetsane',
      latitude: -29.3485,
      longitude: 27.4520,
      baseFee: 50.0,
      distanceFromCenterKm: 9.0,
    ),
    DeliveryLandmark(
      name: 'Ha Leqele',
      latitude: -29.3620,
      longitude: 27.5270,
      baseFee: 50.0,
      distanceFromCenterKm: 9.6,
    ),
    DeliveryLandmark(
      name: 'Ha Abia',
      latitude: -29.3670,
      longitude: 27.5410,
      baseFee: 50.0,
      distanceFromCenterKm: 10.0,
    ),

    // --- M60 Zone ---
    DeliveryLandmark(
      name: 'Masowe 1',
      latitude: -29.3410,
      longitude: 27.4890,
      baseFee: 60.0,
      distanceFromCenterKm: 4.1,
    ),
    DeliveryLandmark(
      name: 'Sehlabeng',
      latitude: -29.3105,
      longitude: 27.5580,
      baseFee: 60.0,
      distanceFromCenterKm: 7.7,
    ),
    DeliveryLandmark(
      name: 'Masianokeng',
      latitude: -29.3902,
      longitude: 27.5603,
      baseFee: 60.0,
      distanceFromCenterKm: 11.4,
    ),
    DeliveryLandmark(
      name: 'Ha Foso',
      latitude: -29.2740,
      longitude: 27.5615,
      baseFee: 60.0,
      distanceFromCenterKm: 11.8,
    ),

    // --- M70 Zone ---
    DeliveryLandmark(
      name: 'Masowe 3',
      latitude: -29.3630,
      longitude: 27.4740,
      baseFee: 70.0,
      distanceFromCenterKm: 12.3,
    ),
    DeliveryLandmark(
      name: 'Maqhaka',
      latitude: -29.2550,
      longitude: 27.6080,
      baseFee: 70.0,
      distanceFromCenterKm: 16.9,
    ),
  ];

  /// Calculates the great-circle distance between two coordinates in kilometers using Haversine formula.
  static double calculateDistanceKm({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const double earthRadiusKm = 6371.0;
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  /// Calculates dynamic delivery fee with spatial interpolation for in-between locations.
  static DeliveryPricingResult calculateDeliveryFee({
    required double latitude,
    required double longitude,
  }) {
    final double distFromCenter = calculateDistanceKm(
      lat1: latitude,
      lon1: longitude,
      lat2: centerLat,
      lon2: centerLng,
    );

    // Compute distance to each known landmark
    final List<MapEntry<DeliveryLandmark, double>> landmarkDistances = [];
    for (final landmark in landmarks) {
      final double d = calculateDistanceKm(
        lat1: latitude,
        lon1: longitude,
        lat2: landmark.latitude,
        lon2: landmark.longitude,
      );
      landmarkDistances.add(MapEntry(landmark, d));
    }

    // Sort by distance ascending
    landmarkDistances.sort((a, b) => a.value.compareTo(b.value));

    final nearest1 = landmarkDistances[0];
    final nearest2 = landmarkDistances.length > 1 ? landmarkDistances[1] : null;
    final nearest3 = landmarkDistances.length > 2 ? landmarkDistances[2] : null;

    double calculatedFee;
    String primaryArea = nearest1.key.name;
    String? secondaryArea;

    // If extremely close to a landmark (< 400m), use its exact base fee
    if (nearest1.value <= 0.4) {
      calculatedFee = nearest1.key.baseFee;
    } else {
      // Inverse Distance Weighting (IDW) interpolation among closest 3 landmarks
      // Power parameter p = 2 gives smooth natural interpolation between zones
      const double p = 2.0;
      double weightedSum = 0.0;
      double weightSum = 0.0;

      final topLandmarks = [nearest1, ?nearest2, ?nearest3];
      for (final entry in topLandmarks) {
        // Distance epsilon to avoid division by zero
        final double dist = math.max(entry.value, 0.05);
        final double weight = 1.0 / math.pow(dist, p);
        weightedSum += entry.key.baseFee * weight;
        weightSum += weight;
      }

      calculatedFee = weightSum > 0 ? (weightedSum / weightSum) : nearest1.key.baseFee;

      if (nearest2 != null && (nearest2.value - nearest1.value).abs() < 2.5) {
        secondaryArea = nearest2.key.name;
      }
    }

    // Guardrail: Minimum delivery fee in urban Maseru is M40
    if (calculatedFee < 40.0) {
      calculatedFee = 40.0;
    }

    // Outlier / Extended Distance Adjustment:
    // If the customer is further out than Maqhaka / furthest landmarks (> 17km from City Centre),
    // scale smoothly beyond M70 by ~M3.50 per additional km.
    if (distFromCenter > 17.0) {
      final double extraKm = distFromCenter - 17.0;
      calculatedFee = math.max(calculatedFee, 70.0 + (extraKm * 3.5));
    }

    // Round to clean whole integer for user-friendly pricing (e.g. 55.0, 56.0, etc.)
    final double finalFee = calculatedFee.roundToDouble();
    final int feeCents = (finalFee * 100).round();

    return DeliveryPricingResult(
      feeAmount: finalFee,
      feeCents: feeCents,
      distanceFromCenterKm: distFromCenter,
      primaryAreaName: primaryArea,
      secondaryAreaName: secondaryArea,
      distanceToPrimaryKm: nearest1.value,
    );
  }
}
