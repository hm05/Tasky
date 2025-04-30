import 'package:flutter/material.dart';

void main() { runApp(const TaskyApp()); }

class TaskyApp extends StatelessWidget { const TaskyApp({super.key});

@override Widget build(BuildContext context) { return MaterialApp( title: 'Tasky', theme: ThemeData( primarySwatch: Colors.blue, ), home: const TaskyList(title: 'Tasky'), ); } }

class TaskyList extends StatefulWidget { const TaskyList({super.key, required this.title});

final String title;

@override State<TaskyList> createState() => _TaskyListState(); }

class _TaskyListState extends State<TaskyList> { final List<Task> _tasks = <Task>[]; final TextEditingController _textFieldController = TextEditingController();

void _addTaskItem(String name) { setState(() { _tasks.add(Task(name: name, completed: false)); }); _textFieldController.clear(); }

void _handleTaskChange(Task task) { setState(() { task.completed = !task.completed; }); }

void _deleteTask(Task task) { setState(() { _tasks.removeWhere((element) => element.name == task.name); }); }

@override Widget build(BuildContext context) { return Scaffold( appBar: AppBar( title: Text(widget.title), ), body: ListView( padding: const EdgeInsets.symmetric(vertical: 8.0), children: _tasks.map((Task task) { return TaskItem( task: task, onTaskChanged: _handleTaskChange, removeTask: _deleteTask, ); }).toList(), ), floatingActionButton: FloatingActionButton( onPressed: () => _displayAddTaskDialog(), tooltip: 'Add a Task', child: const Icon(Icons.add), ), ); }

Future<void> _displayAddTaskDialog() async { return showDialog<void>( context: context, barrierDismissible: false, builder: (BuildContext context) { return AlertDialog( title: const Text('Add a Task'), content: TextField( controller: _textFieldController, decoration: const InputDecoration(hintText: 'Type your task'), autofocus: true, ), actions: <Widget>[ OutlinedButton( onPressed: () { Navigator.of(context).pop(); }, child: const Text('Cancel'), ), ElevatedButton( onPressed: () { Navigator.of(context).pop(); _addTaskItem(_textFieldController.text); }, child: const Text('Add'), ), ], ); }, ); } }

class Task { Task({required this.name, required this.completed}); String name; bool completed; }

class TaskItem extends StatelessWidget { const TaskItem({ required this.task, required this.onTaskChanged, required this.removeTask, super.key, });

final Task task; final void Function(Task task) onTaskChanged; final void Function(Task task) removeTask;

TextStyle? _getTextStyle(bool checked) { if (!checked) return null; return const TextStyle( color: Colors.black54, decoration: TextDecoration.lineThrough, ); }

@override Widget build(BuildContext context) { return ListTile( onTap: () { onTaskChanged(task); }, leading: Checkbox( checkColor: Colors.greenAccent, activeColor: Colors.red, value: task.completed, onChanged: (value) { onTaskChanged(task); }, ), title: Row( children: <Widget>[ Expanded( child: Text(task.name, style: _getTextStyle(task.completed)), ), IconButton( iconSize: 30, icon: const Icon( Icons.delete, color: Colors.red, ), onPressed: () { removeTask(task); }, ), ], ), ); }

}
