import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

void main() {
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

class _TaskyListState extends State<TaskyList> {
  final List<Task> _tasks = <Task>[];
  final TextEditingController _textFieldController = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  bool _speechEnabled = false;
  String _lastWords = '';
  String _feedbackText = '';
  bool _isListening = false;
  String _filterMode = 'all'; // all, completed, pending
  
  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    _speechEnabled = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (errorNotification) {
        setState(() {
          _feedbackText = 'Error: ${errorNotification.errorMsg}';
        });
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

  void _processVoiceCommand(String command) {
    command = command.toLowerCase();
    setState(() {
      _feedbackText = 'Processing: "$command"';
    });

    // Add task command
    if (command.startsWith('add ')) {
      final taskName = command.substring(4).trim();
      if (taskName.isNotEmpty) {
        _addTaskItem(taskName);
        _feedbackText = 'Added task: "$taskName"';
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
      
      _markTaskAsDone(taskText);
    }
    
    // Delete task command
    else if (command.startsWith('delete ') || command.startsWith('remove ')) {
      final taskName = command.startsWith('delete ') 
          ? command.substring(7).trim() 
          : command.substring(7).trim();
      _deleteTaskByName(taskName);
    }
    
    // Show tasks commands
    else if (command.contains('show') || command.contains('list')) {
      if (command.contains('complete')) {
        setState(() {
          _filterMode = 'completed';
          _feedbackText = 'Showing completed tasks';
        });
      } else if (command.contains('pending') || command.contains('incomplete') || command.contains('not complete')) {
        setState(() {
          _filterMode = 'pending';
          _feedbackText = 'Showing pending tasks';
        });
      } else if (command.contains('all')) {
        setState(() {
          _filterMode = 'all';
          _feedbackText = 'Showing all tasks';
        });
      }
    }
    
    // Edit task command
    else if (command.contains('change ') || command.contains('edit ') || command.contains('update ')) {
      _processEditCommand(command);
    }
    
    // Help command
    else if (command.contains('help') || command.contains('commands')) {
      _showHelpDialog();
    }
    
    else {
      setState(() {
        _feedbackText = 'Unrecognized command. Say "help" for assistance.';
      });
    }
  }
  
  void _addTaskItem(String name) {
    setState(() {
      _tasks.add(Task(name: name, completed: false));
      _textFieldController.clear();
    });
  }

  void _handleTaskChange(Task task) {
    setState(() {
      task.completed = !task.completed;
    });
  }

  void _deleteTask(Task task) {
    setState(() {
      _tasks.removeWhere((element) => element.name == task.name);
    });
  }
  
  void _markTaskAsDone(String taskName) {
    bool found = false;
    setState(() {
      for (var task in _tasks) {
        if (task.name.toLowerCase().contains(taskName.toLowerCase())) {
          task.completed = true;
          found = true;
          _feedbackText = 'Marked "${task.name}" as complete';
          break;
        }
      }
      if (!found) {
        _feedbackText = 'Could not find task: "$taskName"';
      }
    });
  }
  
  void _deleteTaskByName(String taskName) {
    bool found = false;
    setState(() {
      for (var i = 0; i < _tasks.length; i++) {
        if (_tasks[i].name.toLowerCase().contains(taskName.toLowerCase())) {
          _tasks.removeAt(i);
          found = true;
          _feedbackText = 'Deleted task containing: "$taskName"';
          break;
        }
      }
      if (!found) {
        _feedbackText = 'Could not find task: "$taskName"';
      }
    });
  }
  
  void _processEditCommand(String command) {
    // Command format: "change X to Y" or "edit X to Y"
    String originalCommand = command;
    RegExp editRegex = RegExp(r'(change|edit|update)\s+(.+?)\s+to\s+(.+)');
    var match = editRegex.firstMatch(command);
    
    if (match != null && match.groupCount >= 3) {
      String oldTaskPart = match.group(2)!;
      String newTaskDesc = match.group(3)!;
      
      bool found = false;
      setState(() {
        for (var task in _tasks) {
          if (task.name.toLowerCase().contains(oldTaskPart.toLowerCase())) {
            task.name = newTaskDesc;
            found = true;
            _feedbackText = 'Updated task to: "$newTaskDesc"';
            break;
          }
        }
        if (!found) {
          _feedbackText = 'Could not find task containing: "$oldTaskPart"';
        }
      });
    } else {
      setState(() {
        _feedbackText = 'Edit command not recognized. Try "edit [task] to [new description]"';
      });
    }
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
        title: Text(widget.title),
        actions: [
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

class Task {
  Task({required this.name, required this.completed});
  String name;
  bool completed;
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
        checkColor: Colors.greenAccent,
        activeColor: Colors.red,
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
            icon: const Icon(
              Icons.delete,
              color: Colors.red,
            ),
            onPressed: () {
              removeTask(task);
            },
          ),
        ],
      ),
    );
  }
}