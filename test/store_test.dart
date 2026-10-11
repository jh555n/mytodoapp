import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:dayweave/data/store.dart';
import 'package:dayweave/domain/models.dart';

void main() {
  sqfliteFfiInit();
  test('Todo and per-occurrence completion survive a reload', () async {
    final directory =
        await Directory.systemTemp.createTemp('dayweave-persistence-');
    final path = '${directory.path}/todos.db';
    var store = await TodoStore.open(factory: databaseFactoryFfi, path: path);
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    final at = DateTime(2026, 10, 12);
    final todo = Todo(
        id: 'persisted',
        title: '저장 확인',
        createdAt: at,
        updatedAt: at,
        startsAt: at,
        anchorAt: at,
        repeat: const RepeatRule(unit: RepeatUnit.week));
    await store.saveTodo(todo);
    await store.complete(todo.id, at, true);
    await store.close();
    store = await TodoStore.open(factory: databaseFactoryFfi, path: path);
    expect((await store.todos()).single.toJson(), todo.toJson());
    expect(await store.completions(), {'persisted@${at.toIso8601String()}'});
    await store.complete(todo.id, at, false);
    expect(await store.completions(), isEmpty);
    await store.deleteTodo(todo.id);
    expect(await store.todos(), isEmpty);
  });
}
