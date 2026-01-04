import 'package:hive/hive.dart';

part 'video_note.g.dart';

@HiveType(typeId: 3)
class VideoNote extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String path;
  @HiveField(2)
  String title;
  @HiveField(3)
  DateTime date;

  VideoNote({
    required this.id,
    required this.path,
    required this.title,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'path': path,
    'title': title,
    'date': date.toIso8601String(),
  };

  static VideoNote fromMap(Map<String, dynamic> map) => VideoNote(
    id: map['id'],
    path: map['path'],
    title: map['title'],
    date: DateTime.parse(map['date']),
  );
} 