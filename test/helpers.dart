import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/local_date.dart';
import 'package:tasklet/core/models.dart';

final t0 = DateTime.utc(2026, 10, 1, 9);

DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

LocalDate d(String s) => LocalDate.parse(s);

Task task(
  String id, {
  int number = 1,
  String title = 'Task',
  String description = '',
  TaskStatus status = TaskStatus.todo,
  Priority priority = Priority.none,
  LocalDate? start,
  LocalDate? due,
  List<String> labels = const [],
  double sortOrder = 0,
  DateTime? created,
  DateTime? updated,
  DateTime? completed,
}) => Task(
  id: id,
  number: number,
  title: title,
  description: description,
  status: status,
  priority: priority,
  startDate: start,
  dueDate: due,
  labelIds: labels,
  sortOrder: sortOrder,
  createdAt: created ?? t0,
  updatedAt: updated ?? created ?? t0,
  completedAt: completed,
);

Project project(
  String id, {
  String name = 'Project',
  String key = 'PRO',
  DateTime? created,
  List<Task> tasks = const [],
  List<Label> labels = const [],
  bool archived = false,
  int? nextNumber,
}) => Project(
  id: id,
  name: name,
  key: key,
  color: TaskletColor.blue,
  archived: archived,
  labels: labels,
  nextNumber: nextNumber,
  createdAt: created ?? t0,
  updatedAt: created ?? t0,
  tasks: tasks,
);

ProjectTask entry(Task t, [Project? p]) => ProjectTask(p ?? project('p1', key: 'WEB'), t);
