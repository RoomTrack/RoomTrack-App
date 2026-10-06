import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';
import 'my_tasks_page.dart';

/// Admin and reception spread cleaning across the team (US-05).
class AssignCleaningPage extends StatelessWidget {
  const AssignCleaningPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final team = store.staffOf(UserRole.housekeeping);
      final open = store.openTasks;
      final roomsWithoutTask = store.rooms
          .where((r) => r.status == RoomStatus.dirty && !open.any((t) => t.roomId == r.id))
          .toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Asignación automática', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Las tareas nuevas van al colaborador con menos carga.'),
              value: store.autoAssignCleaning,
              onChanged: (value) {
                store.autoAssignCleaning = value;
                store.runChecks();
              },
            ),
          ),
          const SectionHeader(title: 'Carga del equipo'),
          for (final member in team)
            BarRow(
              label: member.name,
              value: store.openLoad(member.id).toDouble(),
              max: open.isEmpty ? 1 : open.length.toDouble(),
              display: '${store.openLoad(member.id)} tareas',
            ),
          if (roomsWithoutTask.isNotEmpty) ...[
            const SectionHeader(title: 'Sin tarea creada'),
            Wrap(
              spacing: 8,
              children: [
                for (final room in roomsWithoutTask)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text('Hab. ${room.number}'),
                    onPressed: () => store.createCleaningTask(room.id),
                  ),
              ],
            ),
          ],
          SectionHeader(title: 'Tareas abiertas', subtitle: '${open.length} en curso o pendientes'),
          if (open.isEmpty) const EmptyState(message: 'No hay tareas abiertas.'),
          for (final task in open)
            TaskCard(
              task: task,
              store: store,
              trailing: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_search_outlined),
                      label: Text(task.assigneeId == null ? 'Asignar' : store.userName(task.assigneeId), overflow: TextOverflow.ellipsis),
                      onPressed: () => _pickAssignee(context, store, task, team),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<Priority>(
                    tooltip: 'Cambiar prioridad',
                    icon: const Icon(Icons.flag_outlined),
                    onSelected: (p) => store.setTaskPriority(task.id, p),
                    itemBuilder: (_) => [for (final p in Priority.values) PopupMenuItem(value: p, child: Text(p.label))],
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  Future<void> _pickAssignee(BuildContext context, HotelStore store, CleaningTask task, List<AppUser> team) async {
    final userId = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(task.assigneeId == null ? 'Asignar a' : 'Reasignar a', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          for (final member in team)
            ListTile(
              leading: UserAvatar(member),
              title: Text(member.name),
              subtitle: Text('${store.openLoad(member.id)} tareas abiertas'),
              trailing: member.id == task.assigneeId ? const Icon(Icons.check, color: kSuccess) : null,
              onTap: () => Navigator.pop(sheetContext, member.id),
            ),
        ],
      ),
    );
    if (userId == null || !context.mounted) return;
    runAction(context, () => store.assignTask(task.id, userId), success: 'Tarea asignada a ${store.userName(userId)}.');
  }
}
