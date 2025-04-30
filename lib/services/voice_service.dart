import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  double _volume = 1.0;
  double _pitch = 1.0;
  double _rate = 0.5;
  
  // Singleton pattern
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  
  VoiceService._internal();
  
  Future<void> initialize() async {
    if (!_isInitialized) {
      await _flutterTts.setVolume(_volume);
      await _flutterTts.setPitch(_pitch);
      await _flutterTts.setSpeechRate(_rate);
      _isInitialized = true;
    }
  }
  
  Future<void> speak(String text) async {
    await initialize();
    await _flutterTts.speak(text);
  }
  
  Future<void> stop() async {
    await _flutterTts.stop();
  }
  
  // Voice feedback methods
  Future<void> confirmTaskAdded(String taskName) async {
    await speak('Task added: $taskName');
  }
  
  Future<void> confirmTaskCompleted(String taskName) async {
    await speak('Task marked as complete: $taskName');
  }
  
  Future<void> confirmTaskDeleted(String taskName) async {
    await speak('Task deleted: $taskName');
  }
  
  Future<void> confirmTasksFiltered(String filter) async {
    await speak('Showing $filter tasks');
  }
  
  Future<void> askForClarification(String question) async {
    await speak(question);
  }
  
  Future<void> notifyOfflineMode() async {
    await speak('You are currently offline. Your changes will sync when you reconnect.');
  }
  
  Future<void> notifySyncComplete() async {
    await speak('All your tasks have been synchronized');
  }
  
  Future<void> notifyError(String error) async {
    await speak('Error: $error');
  }
}