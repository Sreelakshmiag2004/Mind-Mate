// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_note.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ImageNoteAdapter extends TypeAdapter<ImageNote> {
  @override
  final int typeId = 2;

  @override
  ImageNote read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ImageNote(
      id: fields[0] as String,
      path: fields[1] as String,
      title: fields[2] as String,
      date: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ImageNote obj) {
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
      other is ImageNoteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
