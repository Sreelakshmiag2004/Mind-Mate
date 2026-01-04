// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VoiceNoteAdapter extends TypeAdapter<VoiceNote> {
  @override
  final int typeId = 0;

  @override
  VoiceNote read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VoiceNote(
      id: fields[0] as String,
      title: fields[1] as String,
      url: fields[2] as String,
      localPath: fields[3] as String,
      date: fields[4] as DateTime,
      duration: fields[5] as Duration,
    );
  }

  @override
  void write(BinaryWriter writer, VoiceNote obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.url)
      ..writeByte(3)
      ..write(obj.localPath)
      ..writeByte(4)
      ..write(obj.date)
      ..writeByte(5)
      ..write(obj.duration);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceNoteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
