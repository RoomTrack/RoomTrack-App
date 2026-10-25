import 'package:flutter/material.dart';

import '../../core/backend/remote_hotel.dart';
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
      final cloud = store.cleaningBackend;
      // In the backend only an administrator changes how the hotel assigns its tasks.
      final canToggle = cloud == null || store.currentUser?.role == UserRole.admin;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Asignación automática', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(canToggle
                  ? 'Las tareas nuevas van al colaborador con menos carga.'
                  : 'Las tareas nuevas van al colaborador con menos carga. Solo el administrador la cambia.'),
              value: store.autoAssignCleaning,
              onChanged: !canToggle
                  ? null
                  : (value) {
                      if (cloud != null) {
                        runAsync(context, () => cloud.setAutoAssignCleaning(value),
                            success: value ? 'Asignación automática activada.' : 'Asignación automática desactivada.');
                        return;
                      }
                      store.autoAssignCleaning = value;
                      store.runChecks();
                    },
            ),
          ),
          const SectionHeader(title: 'Carga del equipo'),
          if (team.isEmpty && cloud != null)
            const InfoRow(Icons.info_outline, 'Tu rol no ve la lista del equipo: asigna "Automática" y el sistema elige a quien tenga menos carga.'),
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
                    onPressed: () => cloud == null
                        ? store.createCleaningTask(room.id)
                        : runAsync(context, () => cloud.createCleaningTask(room.id), success: 'Tarea creada para la habitación ${room.number}.'),
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
                    onSelected: (p) => cloud == null
                        ? store.setTaskPriority(task.id, p)
                        : runAsync(context, () => cloud.setCleaningTaskPriority(task.id, p), success: 'Prioridad cambiada a ${p.label.toLowerCase()}.'),
                    itemBuilder: (_) => [for (final p in Priority.values) PopupMenuItem(value: p, child: Text(p.label))],
                  ),
                  if (cloud != null)
                    IconButton(
                      tooltip: 'Cancelar tarea',
                      icon: const Icon(Icons.close),
                      onPressed: () => _cancel(context, store, cloud, task),
                    ),
                ],
              ),
            ),
        ],
      );
    });
  }

  Future<void> _pickAssignee(BuildContext context, HotelStore store, CleaningTask task, List<AppUser> team) async {
    final cloud = store.cleaningBackend;
    // -1: automatic (the backend picks the least loaded housekeeper).
    final userId = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(task.assigneeId == null ? 'Asignar a' : 'Reasignar a', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if (cloud != null)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.auto_mode)),
              title: const Text('Automática'),
              subtitle: const Text('A quien tenga menos tareas abiertas'),
              onTap: () => Navigator.pop(sheetContext, -1),
            ),
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
    if (cloud != null) {
      await runAsync(context, () => cloud.assignCleaningTask(task.id, userId == -1 ? null : userId),
          success: userId == -1 ? 'Tarea asignada automáticamente.' : 'Tarea asignada a ${store.userName(userId)}.');
      return;
    }
    runAction(context, () => store.assignTask(task.id, userId), success: 'Tarea asignada a ${store.userName(userId)}.');
  }

  Future<void> _cancel(BuildContext context, HotelStore store, RemoteHotel cloud, CleaningTask task) async {
    final room = store.roomById(task.roomId);
    final reason = await askText(context, title: 'Cancelar la tarea de la habitación ${room.number}', label: 'Motivo (opcional)');
    if (reason == null || !context.mounted) return;
    await runAsync(context, () => cloud.cancelCleaningTask(task.id, reason: reason),
        success: 'Tarea cancelada. El estado de la habitación no cambió.');
  }
}
