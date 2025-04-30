import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'models/task.dart';
import 'services/firebase_service.dart';
import 'services/voice_service.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize services
  final firebaseService = FirebaseService();
  final voiceService = VoiceService();
  
  await firebaseService.initialize();
  await voiceService.initialize();
  
  runApp(const TaskyApp());
}

class TaskyApp extends StatelessWidget {
  const TaskyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tasky',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const TaskyList(title: 'Tasky'),
    );
  }
}

class TaskyList extends StatefulWidget {
  const TaskyList({super.key, required this.title});

  final String title;

  @override
  State<TaskyList> createState() => _TaskyListState();
}

class _TaskyListState extends State<TaskyList> with WidgetsBindingObserver {
  final List<Task> _tasks = <Task>[];
  final TextEditingController _textFieldController = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  final FirebaseService _firebaseService = FirebaseService();
  final VoiceService _voiceService = VoiceService();
  final Connectivity _connectivity = Connectivity();
  
  bool _speechEnabled = false;
  bool _isOnline = true;
  bool _isSyncing = false;
  String _lastWords = '';
  String _feedbackText = '';
  bool _isListening = false;
  String _filterMode = 'all'; // all, completed, pending
  List<String> _pendingVoiceCommands = [];
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkConnectivity();
    }
  }
  
  Future<void> _initServices() async {
    // Initialize speech recognition
    _initSpeech();
    
    // Check initial connectivity
    await _checkConnectivity();
    
    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
      
      if (_isOnline) {
        _syncPendingCommands();
        if (_pendingVoiceCommands.isEmpty) {
          _voiceService.notifySyncComplete();
        }
      } else {
        _voiceService.notifyOfflineMode();
      }
    });
    
    // Subscribe to task updates
    _firebaseService.addTaskListener((tasks) {
      setState(() {
        _tasks.clear();
        _tasks.addAll(tasks);
      });
    });
  }
  
  Future<void> _checkConnectivity() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    final result = connectivityResult.isNotEmpty ? connectivityResult.first : ConnectivityResult.none;
    
    setState(() {
      _isOnline = result != ConnectivityResult.none;
    });
  }
  
  void _initSpeech() async {
    _speechEnabled = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (errorNotification) {
        setState(() {
          _feedbackText = 'Error: ${errorNotification.errorMsg}';
        });
        _voiceService.notifyError(errorNotification.errorMsg ?? 'Speech recognition failed');
        print('Speech error: $errorNotification');
      },
    );
    setState(() {});
  }

  void _onSpeechStatus(String status) {
    print('Speech status: $status');
    if (status == 'done') {
      setState(() {
        _isListening = false;
      });
      // Process the command after speech is done
      _processVoiceCommand(_lastWords);
    }
  }

  void _startListening() async {
    setState(() {
      _feedbackText = 'Listening...';
      _isListening = true;
    });
    
    await _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
      _feedbackText = 'Heard: ${result.recognizedWords}';
    });
  }
  
  Future<void> _processVoiceCommand(String command) async {
    if (command.isEmpty) return;
    
    command = command.toLowerCase();
    setState(() {
      _feedbackText = 'Processing: "$command"';
    });

    // Store command for offline processing if needed
    if (!_isOnline) {
      _pendingVoiceCommands.add(command);
      await _voiceService.notifyOfflineMode();
    }

    // Add task command
    if (command.startsWith('add ')) {
      final taskName = command.substring(4).trim();
      if (taskName.isNotEmpty) {
        await _addTaskItem(taskName);
        await _voiceService.confirmTaskAdded(taskName);
      } else {
        await _voiceService.askForClarification('What task would you like to add?');
      }
    }
    
    // Mark completed command
    else if (command.contains(' as done') || command.contains(' as complete') || command.contains(' as completed')) {
      String taskText = '';
      if (command.contains(' as done')) {
        taskText = command.substring(0, command.indexOf(' as done')).replaceFirst('mark ', '').trim();
      } else if (command.contains(' as complete')) {
        taskText = command.substring(0, command.indexOf(' as complete')).replaceFirst('mark ', '').trim();
      } else {
        taskText = command.substring(0, command.indexOf(' as completed')).replaceFirst('mark ', '').trim();
      }
      
      if (taskText.isNotEmpty) {
        await _markTaskAsDone(taskText);
      } else {
        await _voiceService.askForClarification('Which task would you like to mark as complete?');
      }
    }
    
    // Delete task command
    else if (command.startsWith('delete ') || command.startsWith('remove ')) {
      final taskName = command.startsWith('delete ') 
          ? command.substring(7).trim() 
          : command.substring(7).trim();
      
      if (taskName.isNotEmpty) {
        await _deleteTaskByName(taskName);
      } else {
        await _voiceService.askForClarification('Which task would you like to delete?');
      }
    }
    
    // Show tasks commands
    else if (command.contains('show') || command.contains('list')) {
      if (command.contains('complete')) {
        setState(() {
          _filterMode = 'completed';
          _feedbackText = 'Showing completed tasks';
        });
        await _voiceService.confirmTasksFiltered('completed');
      } else if (command.contains('pending') || command.contains('incomplete') || command.contains('not complete')) {
        setState(() {
          _filterMode = 'pending';
          _feedbackText = 'Showing pending tasks';
        });
        await _voiceService.confirmTasksFiltered('pending');
      } else if (command.contains('all')) {
        setState(() {
          _filterMode = 'all';
          _feedbackText = 'Showing all tasks';
        });
        await _voiceService.confirmTasksFiltered('all');
      }
    }
    
    // Edit task command
    else if (command.contains('change ') || command.contains('edit ') || command.contains('update ')) {
      await _processEditCommand(command);
    }
    
    // Help command
    else if (command.contains('help') || command.contains('commands')) {
      _showHelpDialog();
      await _voiceService.speak('Here are the available voice commands.');
    }
    
    else {
      setState(() {
        _feedbackText = 'Unrecognized command. Say "help" for assistance.';
      });
      await _voiceService.speak('I didn\'t understand that command. Say "help" to see available commands.');
    }
  }
  
  Future<void> _syncPendingCommands() async {
    if (_pendingVoiceCommands.isEmpty) return;
    
    setState(() {
      _isSyncing = true;
    });
    
    final commands = List<String>.from(_pendingVoiceCommands);
    _pendingVoiceCommands.clear();
    
    for (var command in commands) {
      await _processVoiceCommand(command);
    }
    
    setState(() {
      _isSyncing = false;
    });
  }
  
  Future<void> _addTaskItem(String name) async {
    await _firebaseService.addTask(name);
    _textFieldController.clear();
  }

  void _handleTaskChange(Task task) async {
    final updatedTask = task.copyWith(
      completed: !task.completed,
    );
    await _firebaseService.updateTask(updatedTask);
    
    if (updatedTask.completed) {
      await _voiceService.confirmTaskCompleted(updatedTask.name);
    }
  }

  Future<void> _deleteTask(Task task) async {
    await _firebaseService.deleteTask(task);
    await _voiceService.confirmTaskDeleted(task.name);
  }
  
  Future<void> _markTaskAsDone(String taskName) async {
    bool found = false;
    for (var task in _tasks) {
      if (task.name.toLowerCase().contains(taskName.toLowerCase())) {
        if (!task.completed) {
          final updatedTask = task.copyWith(completed: true);
          await _firebaseService.updateTask(updatedTask);
          found = true;
          await _voiceService.confirmTaskCompleted(task.name);
        } else {
          found = true;
          await _voiceService.speak('${task.name} is already completed.');
        }
        break;
      }
    }
    
    if (!found) {
      await _voiceService.speak('I couldn\'t find a task containing "$taskName".');
      setState(() {
        _feedbackText = 'Could not find task: "$taskName"';
      });
    }
  }
  
  Future<void> _deleteTaskByName(String taskName) async {
    bool found = false;
    List<Task> matchingTasks = [];
    
    for (var task in _tasks) {
      if (task.name.toLowerCase().contains(taskName.toLowerCase())) {
        matchingTasks.add(task);
      }
    }
    
    if (matchingTasks.isEmpty) {
      await _voiceService.speak('I couldn\'t find a task containing "$taskName".');
      setState(() {
        _feedbackText = 'Could not find task: "$taskName"';
      });
      return;
    } else if (matchingTasks.length > 1) {
      await _voiceService.speak('I found multiple tasks containing "$taskName". Please be more specific.');
      _showTaskSelectionDialog(matchingTasks, (selectedTask) async {
        await _firebaseService.deleteTask(selectedTask);
        await _voiceService.confirmTaskDeleted(selectedTask.name);
      });
      return;
    }
    
    await _firebaseService.deleteTask(matchingTasks[0]);
    await _voiceService.confirmTaskDeleted(matchingTasks[0].name);
  }
  
  Future<void> _processEditCommand(String command) async {
    RegExp editRegex = RegExp(r'(change|edit|update)\s+(.+?)\s+to\s+(.+)');
    var match = editRegex.firstMatch(command);
    
    if (match != null && match.groupCount >= 3) {
      String oldTaskPart = match.group(2)!;
      String newTaskDesc = match.group(3)!;
      
      List<Task> matchingTasks = [];
      for (var task in _tasks) {
        if (task.name.toLowerCase().contains(oldTaskPart.toLowerCase())) {
          matchingTasks.add(task);
        }
      }
      
      if (matchingTasks.isEmpty) {
        await _voiceService.speak('I couldn\'t find a task containing "$oldTaskPart".');
        setState(() {
          _feedbackText = 'Could not find task: "$oldTaskPart"';
        });
      } else if (matchingTasks.length > 1) {
        await _voiceService.speak('I found multiple tasks containing "$oldTaskPart". Please select one to update.');
        _showTaskSelectionDialog(matchingTasks, (selectedTask) async {
          final updatedTask = selectedTask.copyWith(name: newTaskDesc);
          await _firebaseService.updateTask(updatedTask);
          await _voiceService.speak('Updated task to "$newTaskDesc"');
        });
      } else {
        final task = matchingTasks[0];
        final updatedTask = task.copyWith(name: newTaskDesc);
        await _firebaseService.updateTask(updatedTask);
        await _voiceService.speak('Updated task to "$newTaskDesc"');
      }
    } else {
      await _voiceService.speak('I didn\'t understand your edit command. Please try again with "edit [task] to [new description]"');
      setState(() {
        _feedbackText = 'Edit command not recognized. Try "edit [task] to [new description]"';
      });
    }
  }
  
  void _showTaskSelectionDialog(List<Task> tasks, Function(Task) onTaskSelected) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select a Task'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(tasks[index].name),
                  subtitle: Text(tasks[index].completed ? 'Completed' : 'Pending'),
                  onTap: () {
                    Navigator.of(context).pop();
                    onTaskSelected(tasks[index]);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  List<Task> _getFilteredTasks() {
    if (_filterMode == 'completed') {
      return _tasks.where((task) => task.completed).toList();
    } else if (_filterMode == 'pending') {
      return _tasks.where((task) => !task.completed).toList();
    } else {
      return _tasks;
    }
  }
  
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Voice Commands'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _commandHelp('Add [task]', 'Creates a new task'),
                _commandHelp('Mark [task] as done', 'Marks task as complete'),
                _commandHelp('Delete [task]', 'Removes a task'),
                _commandHelp('Show all tasks', 'Displays all tasks'),
                _commandHelp('Show completed tasks', 'Filters completed tasks'),
                _commandHelp('Show pending tasks', 'Filters pending tasks'),
                _commandHelp('Edit [task] to [new description]', 'Updates a task'),
                _commandHelp('Help', 'Shows this help screen'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
  
  Widget _commandHelp(String command, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(command, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('  $description', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _getFilteredTasks();
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.title),
            if (_isSyncing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
          ],
        ),
        actions: [
          // Online/offline indicator
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              _isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: _isOnline ? Colors.green : Colors.grey,
            ),
          ),
          // Filter menu
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _filterMode = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('All Tasks'),
              ),
              const PopupMenuItem(
                value: 'completed',
                child: Text('Completed Tasks'),
              ),
              const PopupMenuItem(
                value: 'pending',
                child: Text('Pending Tasks'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Feedback area
          Container(
            padding: const EdgeInsets.all(8.0),
            color: _isListening ? Colors.lightBlueAccent.withOpacity(0.3) : Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _feedbackText,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: _isListening ? Colors.blue : Colors.grey,
                    ),
                  ),
                ),
                if (_speechEnabled)
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening ? Colors.red : Colors.grey,
                    ),
                    onPressed: _isListening ? _stopListening : _startListening,
                    tooltip: _isListening ? 'Stop listening' : 'Start listening',
                  ),
              ],
            ),
          ),
          
          // Pending commands indicator
          if (_pendingVoiceCommands.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.amber.withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(Icons.pending_actions, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    '${_pendingVoiceCommands.length} command${_pendingVoiceCommands.length > 1 ? 's' : ''} pending sync',
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            
          // Filter indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Showing: ${_filterMode[0].toUpperCase() + _filterMode.substring(1)} Tasks',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (filteredTasks.isNotEmpty)
                  Text('${filteredTasks.length} ${filteredTasks.length == 1 ? 'task' : 'tasks'}'),
              ],
            ),
          ),
          // Tasks list
          Expanded(
            child: filteredTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.task_alt, size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _tasks.isEmpty
                              ? 'No tasks yet. Say "Add [task]" to get started!'
                              : 'No ${_filterMode} tasks found',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final task = filteredTasks[index];
                      return TaskItem(
                        task: task,
                        onTaskChanged: _handleTaskChange,
                        removeTask: _deleteTask,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _speechEnabled ? _startListening : _displayAddTaskDialog,
        tooltip: _speechEnabled ? 'Voice Command' : 'Add a Task',
        child: Icon(_speechEnabled ? Icons.mic : Icons.add),
      ),
    );
  }

  Future<void> _displayAddTaskDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add a Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _textFieldController,
                decoration: const InputDecoration(hintText: 'Type your task'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              if (_speechEnabled)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _speech.isListening 
                          ? 'Listening...' 
                          : 'Tap to speak',
                      style: TextStyle(
                        fontSize: 12,
                        color: _speech.isListening ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        _speech.isNotListening ? Icons.mic : Icons.mic_off,
                        color: _speech.isListening ? Colors.green : Colors.grey,
                      ),
                      onPressed: _speech.isNotListening
                          ? () async {
                              await _speech.listen(
                                onResult: (result) {
                                  setState(() {
                                    _textFieldController.text = result.recognizedWords;
                                  });
                                },
                              );
                            }
                          : _stopListening,
                    ),
                  ],
                ),
            ],
          ),
          actions: <Widget>[
            OutlinedButton(
              onPressed: () {
                if (_speech.isListening) {
                  _stopListening();
                }
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_speech.isListening) {
                  _stopListening();
                }
                Navigator.of(context).pop();
                if (_textFieldController.text.isNotEmpty) {
                  _addTaskItem(_textFieldController.text);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class TaskItem extends StatelessWidget {
  const TaskItem({
    required this.task,
    required this.onTaskChanged,
    required this.removeTask,
    super.key,
  });

  final Task task;
  final void Function(Task task) onTaskChanged;
  final void Function(Task task) removeTask;

  TextStyle? _getTextStyle(bool checked) {
    if (!checked) return null;
    return const TextStyle(
      color: Colors.black54,
      decoration: TextDecoration.lineThrough,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () {
        onTaskChanged(task);
      },
      leading: Checkbox(
        value: task.completed,
        onChanged: (value) {
          onTaskChanged(task);
        },
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(task.name, style: _getTextStyle(task.completed)),
          ),
          IconButton(
            iconSize: 24,
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () {
              removeTask(task);
            },
          ),
        ],
      ),
    );
  }
}