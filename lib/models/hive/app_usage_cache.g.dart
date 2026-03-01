// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_usage_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppUsageCacheAdapter extends TypeAdapter<AppUsageCache> {
  @override
  final int typeId = 2;

  @override
  AppUsageCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppUsageCache(
      packageName: fields[0] as String,
      appName: fields[1] as String,
      minutesToday: fields[2] as int,
      minutesYesterday: fields[3] as int,
      weeklyAverage: fields[4] as double,
      iconUrl: fields[5] as String?,
      lastUpdated: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, AppUsageCache obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.packageName)
      ..writeByte(1)
      ..write(obj.appName)
      ..writeByte(2)
      ..write(obj.minutesToday)
      ..writeByte(3)
      ..write(obj.minutesYesterday)
      ..writeByte(4)
      ..write(obj.weeklyAverage)
      ..writeByte(5)
      ..write(obj.iconUrl)
      ..writeByte(6)
      ..write(obj.lastUpdated);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUsageCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AppUsageCacheListAdapter extends TypeAdapter<AppUsageCacheList> {
  @override
  final int typeId = 3;

  @override
  AppUsageCacheList read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppUsageCacheList(
      apps: (fields[0] as List).cast<AppUsageCache>(),
      lastUpdated: fields[1] as DateTime,
      lastSyncAttempt: fields[2] as DateTime,
      syncError: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AppUsageCacheList obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.apps)
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
      other is AppUsageCacheListAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
