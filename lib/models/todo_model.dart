class TodoItem {
  final String id, userId, partnerId, title;
  final bool isCompleted;
  final String? completedBy;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? description;
  final DateTime? dueDate;
  final String? priority;

  TodoItem({
    required this.id,
    required this.userId,
    required this.partnerId,
    required this.title,
    required this.isCompleted,
    required this.createdAt,
    this.completedBy,
    this.completedAt,
    this.updatedAt,
    this.description,
    this.dueDate,
    this.priority,
  });

  factory TodoItem.fromMap(Map<String, dynamic> m) => TodoItem(
    id: m['id'] as String,
    userId: m['user_id'] as String,
    partnerId: m['partner_id'] as String,
    title: m['title'] as String,
    isCompleted: m['is_completed'] as bool? ?? false,
    completedBy: m['completed_by'] as String?,
    completedAt: m['completed_at'] != null ? DateTime.tryParse(m['completed_at'].toString()) : null,
    createdAt: DateTime.parse(m['created_at'].toString()),
    updatedAt: m['updated_at'] != null ? DateTime.tryParse(m['updated_at'].toString()) : null,
    description: m['description'] as String?,
    dueDate: m['due_date'] != null ? DateTime.tryParse(m['due_date'].toString()) : null,
    priority: m['priority'] as String?,
  );

  TodoItem copyWith({
    bool? isCompleted,
    String? completedBy,
    DateTime? completedAt,
    DateTime? updatedAt,
  }) => TodoItem(
    id: id,
    userId: userId,
    partnerId: partnerId,
    title: title,
    isCompleted: isCompleted ?? this.isCompleted,
    createdAt: createdAt,
    completedBy: completedBy ?? this.completedBy,
    completedAt: completedAt ?? this.completedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    description: description,
    dueDate: dueDate,
    priority: priority,
  );
}
