import 'menu_item.dart';

class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.description,
    required this.rating,
    required this.deliveryFee,
    required this.isOpen,
    this.serviceType = 'both',
    this.previewItems = const <MenuItem>[],
    this.logoUrl,
  });

  final String id;
  final String name;
  final String description;
  final double rating;
  final int deliveryFee;
  final bool isOpen;
  final String serviceType;
  final List<MenuItem> previewItems;
  final String? logoUrl;

  Restaurant copyWith({
    String? id,
    String? name,
    String? description,
    double? rating,
    int? deliveryFee,
    bool? isOpen,
    String? serviceType,
    List<MenuItem>? previewItems,
    String? logoUrl,
  }) {
    return Restaurant(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      isOpen: isOpen ?? this.isOpen,
      serviceType: serviceType ?? this.serviceType,
      previewItems: previewItems ?? this.previewItems,
      logoUrl: logoUrl ?? this.logoUrl,
    );
  }

  factory Restaurant.fromMap(
    String id,
    Map<String, dynamic> data, {
    List<MenuItem> previewItems = const <MenuItem>[],
  }) {
    return Restaurant(
      id: id,
      name: data['name']?.toString() ?? 'Unnamed restaurant',
      description:
          data['description']?.toString() ?? 'No description available',
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      deliveryFee: (data['delivery_fee'] as num?)?.toInt() ?? 0,
      isOpen: data['is_open'] == false ? false : true,
      serviceType: _normalizeServiceType(data['service_type']),
      previewItems: previewItems,
      logoUrl: data['logo_url']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'rating': rating,
      'delivery_fee': deliveryFee,
      'is_open': isOpen,
      'service_type': serviceType,
      'logo_url': logoUrl,
    };
  }

  static String _normalizeServiceType(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'delivery') {
      return 'delivery';
    }
    if (normalized == 'pickup' ||
        normalized == 'pick-up' ||
        normalized == 'pick up') {
      return 'pickup';
    }
    return 'both';
  }
}
