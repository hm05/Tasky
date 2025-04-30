import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Connectivity _connectivity = Connectivity();
  late final SharedPreferences _prefs;
  late final String _deviceId;
  
  bool _isOnline = true;
  final List<Function(List<Task>)> _taskListeners = [];
  final List<Map<String, dynamic>> _offlineQueue = [];
  
  // Local cache of tasks
  List<Task> _tasks = [];
  
  // Singleton pattern
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  
  FirebaseService._internal();
  
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _deviceId = _prefs.getString('device_id') ?? const Uuid().v4();
    await _prefs.setString('device_id', _deviceId);
    
    // Set up offline persistence
    await FirebaseFirestore.instance.enablePersistence();
    
    // Setup connectivity monitoring
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      _isOnline = result != ConnectivityResult.none;
      if (_isOnline) {
        _processPendingOperations();
      }
    });
    
    // Check initial connectivity
    final connectivityResult = await _connectivity.checkConnectivity();
    final result = connectivityResult.isNotEmpty ? connectivityResult.first : ConnectivityResult.none;
    _isOnline = result != ConnectivityResult.none;
    
    // Load any cached tasks
    _loadOfflineQueue();
    _loadCachedTasks();
    
    // Sign in anonymously if not signed in
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    
    // Start listening for changes if online
    if (_isOnline) {
      _setupTasksListener();
    }
  }
  
  void addTaskListener(Function(List<Task>) listener) {
    _taskListeners.add(listener);
    listener(_tasks); // Immediately notify with current state
  }
  
  void removeTaskListener(Function(List<Task>) listener) {
    _taskListeners.remove(listener);
  }
  
  void _notifyListeners() {
    for (var listener in _taskListeners) {
      listener(_tasks);
    }
  }
  
  void _setupTasksListener() {
    _firestore.collection('tasks')
        .where('userId', isEqualTo: _auth.currentUser?.uid)
        .snapshots()
        .listen((snapshot) {
      if (_isOnline) {
        _tasks = snapshot.docs
            .map((doc) => Task.fromMap(doc.data()))
            .toList();
        
        // Sort by creation date, newest first
        _tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        // Save to local cache
        _saveCachedTasks();
        
        // Notify listeners
        _notifyListeners();
      }
    });
  }
  
  Future<void> addTask(String name) async {
    final task = Task(
      id: const Uuid().v4(),
      name: name,
      deviceId: _deviceId,
    );
    
    // Add to local cache
    _tasks.insert(0, task);
    _notifyListeners();
    _saveCachedTasks();
    
    if (_isOnline) {
      try {
        await _firestore.collection('tasks').doc(task.id).set({
          ...task.toMap(),
          'userId': _auth.currentUser?.uid,
        });
      } catch (e) {
        _queueOperation('add', task.toMap());
      }
    } else {
      _queueOperation('add', task.toMap());
    }
  }
  
  Future<void> updateTask(Task task) async {
    // Update local version first for responsiveness
    final updatedTask = task.copyWith(
      updatedAt: DateTime.now(),
      deviceId: _deviceId,
    );
    
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      _notifyListeners();
      _saveCachedTasks();
    }
    
    if (_isOnline) {
      try {
        await _firestore.runTransaction((transaction) async {
          final docRef = _firestore.collection('tasks').doc(task.id);
          final snapshot = await transaction.get(docRef);
          
          if (snapshot.exists) {
            final serverTask = Task.fromMap(snapshot.data()!);
            
            // Apply conflict resolution rules
            if (serverTask.localVersion > task.localVersion) {
              if (serverTask.deviceId != _deviceId) {
                final mergedTask = updatedTask.copyWith(
                  completed: serverTask.completed,
                  localVersion: serverTask.localVersion + 1,
                );
                
                transaction.update(docRef, {
                  ...mergedTask.toMap(),
                  'userId': _auth.currentUser?.uid,
                });
                
                _tasks[index] = mergedTask;
                _notifyListeners();
                _saveCachedTasks();
              }
            } else {
              transaction.update(docRef, {
                ...updatedTask.toMap(),
                'userId': _auth.currentUser?.uid,
              });
            }
          } else {
            transaction.set(docRef, {
              ...updatedTask.toMap(),
              'userId': _auth.currentUser?.uid,
            });
          }
        });
      } catch (e) {
        _queueOperation('update', updatedTask.toMap());
      }
    } else {
      _queueOperation('update', updatedTask.toMap());
    }
  }
  
  Future<void> deleteTask(Task task) async {
    // Update local cache
    _tasks.removeWhere((t) => t.id == task.id);
    _notifyListeners();
    _saveCachedTasks();
    
    if (_isOnline) {
      try {
        await _firestore.collection('tasks').doc(task.id).delete();
      } catch (e) {
        _queueOperation('delete', {'id': task.id});
      }
    } else {
      _queueOperation('delete', {'id': task.id});
    }
  }
  
  void _queueOperation(String operation, Map<String, dynamic> data) {
    _offlineQueue.add({
      'operation': operation,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    _saveOfflineQueue();
  }
  
  Future<void> _processPendingOperations() async {
    if (_offlineQueue.isEmpty) return;
    
    final operations = List<Map<String, dynamic>>.from(_offlineQueue);
    _offlineQueue.clear();
    _saveOfflineQueue();
    
    for (var op in operations) {
      try {
        switch (op['operation']) {
          case 'add':
            final task = Task.fromMap(op['data']);
            await _firestore.collection('tasks').doc(task.id).set({
              ...task.toMap(),
              'userId': _auth.currentUser?.uid,
            });
            break;
            
          case 'update':
            final task = Task.fromMap(op['data']);
            await _firestore.runTransaction((transaction) async {
              final docRef = _firestore.collection('tasks').doc(task.id);
              final snapshot = await transaction.get(docRef);
              
              if (snapshot.exists) {
                final serverTask = Task.fromMap(snapshot.data()!);
                if (serverTask.localVersion > task.localVersion) {
                  final mergedTask = task.copyWith(
                    name: task.name,
                    completed: serverTask.deviceId != _deviceId ? 
                        serverTask.completed : task.completed,
                    localVersion: serverTask.localVersion + 1,
                  );
                  transaction.update(docRef, {
                    ...mergedTask.toMap(),
                    'userId': _auth.currentUser?.uid,
                  });
                } else {
                  transaction.update(docRef, {
                    ...task.toMap(),
                    'userId': _auth.currentUser?.uid,
                  });
                }
              }
            });
            break;
            
          case 'delete':
            await _firestore.collection('tasks')
                .doc(op['data']['id'])
                .delete();
            break;
        }
      } catch (e) {
        _queueOperation(
          op['operation'],
          op['data'],
        );
      }
    }
  }
  
  // Local persistence
  Future<void> _saveOfflineQueue() async {
    await _prefs.setString(
      'offline_queue',
      jsonEncode(_offlineQueue),
    );
  }
  
  Future<void> _loadOfflineQueue() async {
    final queueJson = _prefs.getString('offline_queue');
    if (queueJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(queueJson);
        _offlineQueue.addAll(
          decoded.map((item) => Map<String, dynamic>.from(item)).toList()
        );
      } catch (e) {
        print('Failed to decode offline queue: $e');
      }
    }
  }
  
  Future<void> _saveCachedTasks() async {
    final taskMaps = _tasks.map((task) => task.toMap()).toList();
    await _prefs.setString('cached_tasks', jsonEncode(taskMaps));
  }
  
  Future<void> _loadCachedTasks() async {
    final tasksJson = _prefs.getString('cached_tasks');
    if (tasksJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(tasksJson);
        _tasks = decoded
            .map((item) => Task.fromMap(Map<String, dynamic>.from(item)))
            .toList();
        _notifyListeners();
      } catch (e) {
        print('Failed to decode cached tasks: $e');
      }
    }
  }
}