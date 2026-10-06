import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../messages/chat_view.dart';

/// Checklist per room type, status updates and comments on the task (US-06, US-07, US-12).
class TaskDetailPage extends StatelessWidget {
  final int taskId;

  const TaskDetailPage({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: StoreBuilder(builder: (context, store) {
        final task = store.taskById(taskId);
        final room = store.roomById(task.roomId);
        final user = store.currentUser!;
        final isAssignee = task.assigneeId == user.id;
        return Scaffold(
          appBar: AppBar(
            title: Text('Habitación ${room.number}', style: const TextStyle(fontWeight: FontWeight.w900)),
            bottom: const TabBar(tabs: [Tab(text: 'Checklist'), Tab(text: 'Comentarios e historial')]),
          ),
          body: TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Checklist ${room.type.label}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            ),
                            PriorityPill(task.priority),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: ProgressLine(task.progress, color: kSuccess)),
                            const SizedBox(width: 10),
                            Text('${(task.progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                          ],
                        ),
                        InfoRow(Icons.person_outline, 'Responsable: ${store.userName(task.assigneeId)}'),
                        InfoRow(Icons.flag_outlined, 'Estado: ${task.status.label}'),
                      ],
                    ),
                  ),
                  for (var i = 0; i < task.checklist.length; i++)
                    CheckboxListTile(
                      value: task.checklist[i].done,
                      onChanged: !task.isOpen || !isAssignee || task.status == TaskStatus.pending
                          ? null
                          : (value) => store.toggleChecklistItem(task.id, i, value ?? false),
                      title: Text(task.checklist[i].label),
                      subtitle: task.checklist[i].required
                          ? (!task.checklist[i].done && task.status == TaskStatus.inProgress
                              ? const Text('Obligatorio', style: TextStyle(color: kError))
                              : const Text('Obligatorio'))
                          : const Text('Opcional'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  const SizedBox(height: 12),
                  if (task.isOpen && isAssignee) ...[
                    if (task.status == TaskStatus.pending)
                      AppButton(
                        text: 'Iniciar limpieza',
                        icon: Icons.play_arrow,
                        onPressed: () => store.startTask(task.id),
                      )
                    else
                      AppButton(
                        text: 'Marcar como limpia',
                        icon: Icons.check_circle_outline,
                        dark: true,
                        onPressed: () {
                          final ok = runAction(context, () => store.completeTask(task.id), success: 'Habitación lista para recepción.');
                          if (ok) Navigator.pop(context);
                        },
                      ),
                    const SizedBox(height: 10),
                    AppButton(
                      text: 'Reportar desperfecto',
                      icon: Icons.report_problem_outlined,
                      outlined: true,
                      onPressed: () => _reportImpediment(context, store, task),
                    ),
                  ],
                  if (task.isOpen && !isAssignee)
                    const InfoRow(Icons.info_outline, 'Solo la persona responsable puede actualizar esta tarea.'),
                ],
              ),
              Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final event in task.events)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.history, size: 18),
                            title: Text(event.text),
                            subtitle: Text(fmtDateTime(event.at)),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SizedBox(height: 280, child: ChatView(channel: HotelStore.taskChannel(task.id))),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _reportImpediment(BuildContext context, HotelStore store, CleaningTask task) async {
    final controller = TextEditingController();
    var urgency = Priority.high;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Reportar desperfecto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(labelText: '¿Qué encontraste?')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final p in Priority.values)
                    ChoiceChip(label: Text(p.label), selected: urgency == p, onSelected: (_) => setLocal(() => urgency = p)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enviar a mantenimiento')),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    runAction(
      context,
      () => store.reportImpediment(task.id, description: controller.text, urgency: urgency, reporterId: store.currentUser!.id),
      success: 'Incidencia creada y enviada a mantenimiento.',
    );
  }
}
