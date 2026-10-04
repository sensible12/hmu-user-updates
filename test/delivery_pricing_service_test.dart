import 'package:flutter_test/flutter_test.dart';
import 'package:hmu/core/services/delivery_pricing_service.dart';

void main() {
  group('DeliveryPricingService Tests', () {
    test('Exact landmark coordinates return exact zone pricing', () {
      // Ha Hoohlo -> M40
      final resultHoohlo = DeliveryPricingService.calculateDeliveryFee(
        latitude: -29.3035,
        longitude: 27.4667,
      );
      expect(resultHoohlo.feeAmount, equals(40.0));
      expect(resultHoohlo.primaryAreaName, equals('Ha Hoohlo'));

      // Khubetsoana -> M50
      final resultKhubetsoana = DeliveryPricingService.calculateDeliveryFee(
        latitude: -29.2811,
        longitude: 27.5352,
      );
      expect(resultKhubetsoana.feeAmount, equals(50.0));
      expect(resultKhubetsoana.primaryAreaName, equals('Khubetsoana'));

      // Ha Foso -> M60
      final resultFoso = DeliveryPricingService.calculateDeliveryFee(
        latitude: -29.2740,
        longitude: 27.5615,
      );
      expect(resultFoso.feeAmount, equals(60.0));
      expect(resultFoso.primaryAreaName, equals('Ha Foso'));

      // Maqhaka -> M70
      final resultMaqhaka = DeliveryPricingService.calculateDeliveryFee(
        latitude: -29.2550,
        longitude: 27.6080,
      );
      expect(resultMaqhaka.feeAmount, equals(70.0));
      expect(resultMaqhaka.primaryAreaName, equals('Maqhaka'));
    });

    test('Midpoint between Khubetsoana (M50) and Ha Foso (M60) interpolates to M55', () {
      // Khubetsoana: -29.2811, 27.5352
      // Ha Foso: -29.2740, 27.5615
      // Midpoint:
      final midLat = (-29.2811 + -29.2740) / 2;
      final midLng = (27.5352 + 27.5615) / 2;

      final resultMid = DeliveryPricingService.calculateDeliveryFee(
        latitude: midLat,
        longitude: midLng,
      );

      // Should be interpolated fairly to M55
      expect(resultMid.feeAmount, equals(55.0));
    });

    test('Locations close to Maseru Town Centre adhere to minimum M40 fee', () {
      final resultCenter = DeliveryPricingService.calculateDeliveryFee(
        latitude: -29.3101,
        longitude: 27.4782,
      );
      expect(resultCenter.feeAmount, greaterThanOrEqualTo(40.0));
    });
  });
}
