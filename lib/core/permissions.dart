import '../domain/models.dart';

/// Every screen of the app. Each role only reaches the features of its job (US-01).
enum Feature {
  dashboard,
  roomsBoard,
  availability,
  myTasks,
  assignCleaning,
  myIncidents,
  incidents,
  reportIncident,
  requests,
  frontDesk,
  payments,
  messages,
  analytics,
  staffAdmin,
  shifts,
  handover,
  preventive,
  alerts,
  reportSchedules,
  myStay,
  services,
  guestHome,
  guestChat,
  profile,
  notifications,
}

const Set<Feature> _common = {Feature.profile, Feature.notifications};

const Set<Feature> _staffCommon = {
  ..._common,
  Feature.messages,
  Feature.requests,
  Feature.reportIncident,
  Feature.handover,
  Feature.shifts,
};

const Map<UserRole, Set<Feature>> _access = {
  UserRole.admin: {
    ..._staffCommon,
    Feature.dashboard,
    Feature.roomsBoard,
    Feature.availability,
    Feature.assignCleaning,
    Feature.incidents,
    Feature.frontDesk,
    Feature.payments,
    Feature.analytics,
    Feature.staffAdmin,
    Feature.preventive,
    Feature.alerts,
    Feature.reportSchedules,
  },
  UserRole.reception: {
    ..._staffCommon,
    Feature.roomsBoard,
    Feature.availability,
    Feature.assignCleaning,
    Feature.frontDesk,
    Feature.payments,
  },
  UserRole.housekeeping: {
    ..._staffCommon,
    Feature.myTasks,
  },
  UserRole.maintenance: {
    ..._staffCommon,
    Feature.myIncidents,
    Feature.preventive,
  },
  UserRole.guest: {
    ..._common,
    Feature.myStay,
    Feature.services,
    Feature.guestHome,
    Feature.guestChat,
  },
};

bool canAccess(UserRole role, Feature feature) => _access[role]?.contains(feature) ?? false;
