import 'package:equatable/equatable.dart';

class Category extends Equatable {
  final String id;
  final String name;
  final String description;
  final String? iconUrl;
  final String? category;
  final int trackCount;

  const Category({
    required this.id,
    required this.name,
    required this.description,
    this.iconUrl,
    this.category,
    required this.trackCount,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'].toString(),
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      category: json['category'] as String?,
      trackCount: json['track_count'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, name, description, iconUrl, category, trackCount];
}
