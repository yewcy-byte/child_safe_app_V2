// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'screen_time_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ScreenTimeCacheAdapter extends TypeAdapter<ScreenTimeCache> {
  @override
  final int typeId = 1;

  @override
  ScreenTimeCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ScreenTimeCache(
      dailyMinutes: (fields[0] as List).cast<int>(),
      lastUpdated: fields[1] as DateTime,
      lastSyncAttempt: fields[2] as DateTime,
      syncError: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ScreenTimeCache obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.dailyMinutes)
      ..writeByte(1)
      ..write(obj.lastUpdated)
      ..writeByte(2)
      ..write(obj.lastSyncAttempt)
      ..writeByte(3)
      ..write(obj.syncError);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenTimeCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
