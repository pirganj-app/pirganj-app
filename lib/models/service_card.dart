class ServiceCard {
  const ServiceCard({
    required this.id,
    required this.name,
    required this.category,
    required this.meta,
    required this.location,
    required this.phone,
    required this.open,
    required this.icon,
  });

  final String id;
  final String name;
  final String category;
  final String meta;
  final String location;
  final String phone;
  final String open;
  final String icon;

  factory ServiceCard.fromJson(Map<String, dynamic> json) => ServiceCard(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        meta: json['meta']?.toString() ?? '',
        location: json['location']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        open: json['open']?.toString() ?? '',
        icon: json['icon']?.toString() ?? '•',
      );
}
