// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_note.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VideoNoteAdapter extends TypeAdapter<VideoNote> {
  @override
  final int typeId = 3;

  @override
  VideoNote read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VideoNote(
      id: fields[0] as String,
      path: fields[1] as String,
      title: fields[2] as String,
      date: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, VideoNote obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.path)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.date);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoNoteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
