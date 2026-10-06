import 'package:flutter/material.dart';

import '../../core/permissions.dart';
import '../../domain/models.dart';
import '../alerts/alerts_page.dart';
import '../analytics/analytics_page.dart';
import '../analytics/report_schedules_page.dart';
import '../dashboard/admin_dashboard_page.dart';
import '../front_desk/front_desk_page.dart';
import '../guest/guest_chat_page.dart';
import '../guest/guest_home_page.dart';
import '../guest/my_stay_page.dart';
import '../guest/services_page.dart';
import '../handover/handover_page.dart';
import '../housekeeping/assign_cleaning_page.dart';
import '../housekeeping/my_tasks_page.dart';
import '../incidents/incidents_page.dart';
import '../incidents/preventive_page.dart';
import '../incidents/report_incident_page.dart';
import '../messages/messages_page.dart';
import '../notifications/notifications_page.dart';
import '../payments/payments_page.dart';
import '../profile/profile_page.dart';
import '../requests/requests_page.dart';
import '../rooms/availability_page.dart';
import '../rooms/rooms_board_page.dart';
import '../shifts/shifts_page.dart';
import '../staff/staff_admin_page.dart';

class FeatureInfo {
  final String title;
  final IconData icon;
  final Widget Function() builder;
  final String subtitle;

  const FeatureInfo(this.title, this.icon, this.builder, [this.subtitle = '']);
}

final Map<Feature, FeatureInfo> featureInfo = {
  Feature.dashboard: FeatureInfo('Panel', Icons.space_dashboard_outlined, () => const AdminDashboardPage(), 'La operación del hotel de un vistazo.'),
  Feature.roomsBoard: FeatureInfo('Habitaciones', Icons.grid_view_outlined, () => const RoomsBoardPage(), 'Estado de cada habitación, en tiempo real.'),
  Feature.availability: FeatureInfo('Disponibilidad', Icons.event_available_outlined, () => const AvailabilityPage(), 'Habitaciones listas para asignar.'),
  Feature.myTasks: FeatureInfo('Mis tareas', Icons.checklist_outlined, () => const MyTasksPage(), 'Tus habitaciones, de la más urgente a la menos.'),
  Feature.assignCleaning: FeatureInfo('Asignar limpieza', Icons.assignment_ind_outlined, () => const AssignCleaningPage()),
  Feature.myIncidents: FeatureInfo('Mis incidencias', Icons.handyman_outlined, () => const IncidentsPage(onlyMine: true), 'Tus incidencias por prioridad y fecha.'),
  Feature.incidents: FeatureInfo('Incidencias', Icons.report_problem_outlined, () => const IncidentsPage(), 'Reportes y su seguimiento hasta resolverse.'),
  Feature.reportIncident: FeatureInfo('Reportar incidencia', Icons.add_alert_outlined, () => const ReportIncidentPage(), 'Avisa a mantenimiento en segundos.'),
  Feature.requests: FeatureInfo('Solicitudes', Icons.room_service_outlined, () => const RequestsPage(), 'Pedidos de los huéspedes y su área.'),
  Feature.frontDesk: FeatureInfo('Recepción', Icons.support_agent, () => const FrontDeskPage(), 'Llegadas, hospedados y salidas.'),
  Feature.payments: FeatureInfo('Pagos y comprobantes', Icons.receipt_long_outlined, () => const PaymentsPage()),
  Feature.messages: FeatureInfo('Mensajes', Icons.forum_outlined, () => const MessagesPage(), 'Coordina con las otras áreas.'),
  Feature.analytics: FeatureInfo('Analítica', Icons.insights_outlined, () => const AnalyticsPage(), 'Productividad, tiempos y satisfacción.'),
  Feature.staffAdmin: FeatureInfo('Personal', Icons.badge_outlined, () => const StaffAdminPage()),
  Feature.shifts: FeatureInfo('Turnos', Icons.calendar_month_outlined, () => const ShiftsPage()),
  Feature.handover: FeatureInfo('Entrega de turno', Icons.swap_horiz, () => const HandoverPage(), 'Lo que el siguiente turno debe saber.'),
  Feature.preventive: FeatureInfo('Preventivo', Icons.event_repeat_outlined, () => const PreventivePage(), 'Mantenimiento que se repite solo.'),
  Feature.alerts: FeatureInfo('Alertas', Icons.notification_important_outlined, () => const AlertsPage()),
  Feature.reportSchedules: FeatureInfo('Reportes programados', Icons.schedule_send_outlined, () => const ReportSchedulesPage()),
  Feature.myStay: FeatureInfo('Mi estadía', Icons.bed_outlined, () => const MyStayPage(), 'Tu estancia, en un solo lugar.'),
  Feature.services: FeatureInfo('Servicios', Icons.room_service_outlined, () => const ServicesPage(), 'Un poco de comodidad cuando la necesites.'),
  Feature.guestHome: FeatureInfo('Inicio', Icons.home_outlined, () => const GuestHomePage()),
  Feature.guestChat: FeatureInfo('Mensajes', Icons.chat_bubble_outline, () => const GuestChatPage(), 'Habla con recepción cuando quieras.'),
  Feature.profile: FeatureInfo('Perfil', Icons.person_outline, () => const ProfilePage(), 'Tus datos y preferencias.'),
  Feature.notifications: FeatureInfo('Notificaciones', Icons.notifications_outlined, () => const NotificationsPage()),
};

/// Bottom navigation per role; whatever else the role can reach lives under "Más".
const Map<UserRole, List<Feature>> roleTabs = {
  UserRole.admin: [Feature.dashboard, Feature.roomsBoard, Feature.incidents, Feature.analytics],
  UserRole.reception: [Feature.frontDesk, Feature.availability, Feature.requests, Feature.messages],
  UserRole.housekeeping: [Feature.myTasks, Feature.reportIncident, Feature.messages, Feature.handover],
  UserRole.maintenance: [Feature.myIncidents, Feature.preventive, Feature.messages, Feature.handover],
  UserRole.guest: [Feature.guestHome, Feature.services, Feature.myStay, Feature.guestChat, Feature.profile],
};

List<Feature> moreFeatures(UserRole role) => Feature.values
    .where((f) => canAccess(role, f) && !roleTabs[role]!.contains(f) && f != Feature.notifications)
    .toList();
