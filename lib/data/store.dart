import 'dart:convert';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import '../domain/models.dart';

class TodoStore {
  TodoStore(this.db);
  final Database db;
  static Future<TodoStore> open(
      {DatabaseFactory? factory, String? path}) async {
    final selectedFactory = factory ?? databaseFactory;
    final databasePath =
        path ?? paths.join(await getDatabasesPath(), 'dayweave.db');
    final db = await selectedFactory.openDatabase(databasePath,
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute(
                  'CREATE TABLE todos (id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
              await db.execute(
                  'CREATE TABLE categories (id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
              await db.execute(
                  'CREATE TABLE settings (key TEXT PRIMARY KEY, payload TEXT NOT NULL)');
              await db.execute(
                  'CREATE TABLE completions (todo_id TEXT NOT NULL, anchor TEXT NOT NULL, PRIMARY KEY(todo_id, anchor))');
            }));
    return TodoStore(db);
  }

  Future<List<Todo>> todos() async => (await db.query('todos'))
      .map((row) => Todo.fromJson(
          jsonDecode(row['payload'] as String) as Map<String, dynamic>))
      .toList();
  Future<List<TodoCategory>> categories() async =>
      (await db.query('categories'))
          .map((row) => TodoCategory.fromJson(
              jsonDecode(row['payload'] as String) as Map<String, dynamic>))
          .toList();
  Future<void> saveTodo(Todo todo) async {
    await db.insert(
        'todos', {'id': todo.id, 'payload': jsonEncode(todo.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveCategory(TodoCategory category) async {
    await db.insert('categories',
        {'id': category.id, 'payload': jsonEncode(category.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTodo(String id) async {
    await db.transaction((txn) async {
      await txn.delete('todos', where: 'id = ?', whereArgs: [id]);
      await txn.delete('completions', where: 'todo_id = ?', whereArgs: [id]);
    });
  }

  Future<void> setValue(String key, Object? value) async {
    await db.insert('settings', {'key': key, 'payload': jsonEncode(value)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<dynamic> value(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['payload'] as String);
  }

  Future<Set<String>> completions() async => (await db.query('completions'))
      .map((row) => '${row['todo_id']}@${row['anchor']}')
      .toSet();
  Future<void> complete(String id, DateTime anchor, bool completed) async {
    if (completed) {
      await db.insert(
          'completions', {'todo_id': id, 'anchor': anchor.toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('completions',
          where: 'todo_id = ? AND anchor = ?',
          whereArgs: [id, anchor.toIso8601String()]);
    }
  }

  Future<void> close() => db.close();
}
