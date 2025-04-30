import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  String name;
  bool completed;
  final DateTime createdAt;
  DateTime updatedAt;
  final String deviceId;
  final int localVersion;
  
  Task({
    required this.id,
    required this.name,
    this.completed = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.deviceId,
    this.localVersion = 0,
  }) : 
    createdAt = createdAt ?? DateTime.now(),
    updatedAt = updatedAt ?? DateTime.now();
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'completed': completed,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'deviceId': deviceId,
      'localVersion': localVersion,
    };
  }
  
  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      name: map['name'] as String,
      completed: map['completed'] as bool,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: (map['updatedAt'] as Timestamp).toDate(),
      deviceId: map['deviceId'] as String,
      localVersion: map['localVersion'] as int,
    );
  }
  
  Task copyWith({
    String? id,
    String? name,
    bool? completed,
    DateTime? updatedAt,
    String? deviceId,
    int? localVersion,
  }) {
    return Task(
      id: id ?? this.id,
      name: name ?? this.name,
      completed: completed ?? this.completed,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      deviceId: deviceId ?? this.deviceId,
      localVersion: localVersion ?? this.localVersion + 1,
    );
  }
}