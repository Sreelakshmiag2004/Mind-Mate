import 'package:hive/hive.dart';

part 'image_note.g.dart';

@HiveType(typeId: 2)
class ImageNote extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String path;
  @HiveField(2)
  String title;
  @HiveField(3)
  final DateTime date;

  ImageNote({
    required this.id,
    required this.path,
    required this.title,
    required this.date,
  });
} 