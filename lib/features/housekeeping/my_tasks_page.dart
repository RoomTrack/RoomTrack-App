import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../handover/handover_page.dart';
import 'task_detail_page.dart';

/// Housekeeper's list, most urgent first and color coded (US-06, US-29).
class MyTasksPage extends StatefulWidget {
  const MyTasksPage({super.key});

  @override
  State<MyTasksPage> createState() => _MyTasksPageState();
}

class _MyTasksPageState extends State<MyTasksPage> {
  bool _onlyCritical = false;

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final user = store.currentUser!;
      final tasks = store.tasksFor(user.id, onlyCritical: _onlyCritical);
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          HandoverBanner(user: user),
          Row(
            children: [
              Expanded(
                child: Text('${tasks.length} ${tasks.length == 1 ? 'habitación' : 'habitaciones'} por atender',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ),
              FilterChip(
                label: const Text('Solo urgencia alta'),
                selected: _onlyCritical,
                onSelected: (value) => setState(() => _onlyCritical = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty) const EmptyState(icon: Icons.celebration_outlined, message: '¡Todo limpio! No tienes tareas pendientes.'),
          for (final task in tasks) TaskCard(task: task, store: store),
        ],
      );
    });
  }
}

class TaskCard extends StatelessWidget {
  final CleaningTask task;
  final HotelStore store;
  final Widget? trailing;

  const TaskCard({super.key, required this.task, required this.store, this.trailing});

  @override
  Widget build(BuildContext context) {
    final room = store.roomById(task.roomId);
    final critical = task.priority.isCritical;
    return AppCard(
      color: critical ? task.priority.color.withAlpha(14) : null,
      borderColor: critical ? task.priority.color : null,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: task.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 40, decoration: BoxDecoration(color: task.priority.color, borderRadius: BorderRadius.circular(9))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Habitación ${room.number}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                    Text('${room.type.label} · Piso ${room.floor} · ${timeAgo(task.createdAt, store.now)}',
                        style: const TextStyle(color: kMuted)),
                  ],
                ),
              ),
              PriorityPill(task.priority),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: ProgressLine(task.progress, color: task.status == TaskStatus.inProgress ? kSuccess : kPrimary)),
              const SizedBox(width: 10),
              Text('${(task.progress * 100).round()}% · ${task.status.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          if (trailing != null) ...[const SizedBox(height: 8), trailing!],
        ],
      ),
    );
  }
}
