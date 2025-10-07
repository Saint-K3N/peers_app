// lib/app.dart
import 'package:flutter/material.dart';
import 'home_page.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';
import 'student_home_page.dart';
import 'admin_home_page.dart';
import 'admin_user_management_page.dart';
import 'past_year_repository_page.dart';
import 'admin_interests_page.dart';
import 'admin_faculty_page.dart';
import 'admin_review_applications_page.dart';
import 'admin_review_reports_page.dart';
import 'school_counsellor_home_page.dart';
import 'school_counsellor_review_applications_page.dart';
import 'school_counsellor_application_detail_page.dart';
import 'school_counsellor_my_counsellors_page.dart';
import 'school_counsellor_booking_info_page.dart';
import 'student_find_help_page.dart';
import 'student_make_appointment_page.dart';
import 'student_booking_info_page.dart';
import 'student_past_year_repository_page.dart';
import 'student_progress_page.dart';
import 'student_review_applications_page.dart';
import 'student_review_application_detail_page.dart';
import 'student_apply_peer_page.dart';
import 'peer_tutor_home_page.dart';
import 'peer_counsellor_home_page.dart';
import 'hop_home_page.dart';
import 'auth_gate.dart';
import 'admin_review_application_detail_page.dart';
import 'hop_review_application_detail_page.dart';
import 'hop_review_applications_page.dart';
import 'student_profile_page.dart';
import 'peer_profile_page.dart';
import 'peer_tutor_schedule_page.dart';
import 'peer_booking_info_page.dart';
import 'peer_tutor_students_page.dart';
import 'peer_tutor_student_detail_page.dart';
import 'peer_tutor_past_year_repository_page.dart';
import 'peer_tutor_profile_page.dart';
import 'peer_counsellor_schedule_page.dart';
import 'peer_counsellor_booking_info_page.dart';
import 'peer_counsellor_peers_page.dart';
import 'peer_counsellor_peer_detail_page.dart';
import 'peer_counsellor_profile_page.dart';
import 'hop_scheduling_page.dart';
import 'hop_my_tutors_page.dart';
import 'hop_tutor_detail_page.dart';
import 'hop_student_report_page.dart';
import 'hop_make_appointment_page.dart';
import 'hop_booking_info_page.dart';
import 'hop_profile_page.dart';
import 'school_counsellor_detail_page.dart';
import 'school_counsellor_make_appointment_page.dart';
import 'school_counsellor_schedule_page.dart';
import 'school_counsellor_profile_page.dart';


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PEERS',
      theme: ThemeData(useMaterial3: true),

      // ⬇️ Let AuthGate decide where to go (login vs role-based home)
      home: const AuthGate(),

      routes: {
        // Auth & onboarding
        '/login': (_) => const MyHomePage(title: 'Login'),
        '/register': (_) => const RegisterPage(),
        '/forgot': (_) => const ForgotPasswordPage(),

        // Student
        '/student/home': (_) => const StudentHomePage(),
        '/student/personal_profile': (_) => const StudentProfilePage(),
        '/student/find-help': (_) => const StudentFindHelpPage(),
        '/student/appointment': (_) => const StudentMakeAppointmentPage(),
        '/student/past-papers': (_) => const StudentPastYearRepositoryPage(),
        '/student/booking-info': (_) => const StudentBookingInfoPage(),
        '/student/progress': (_) => const StudentProgressPage(),
        '/student/review-applications': (_) => const StudentReviewApplicationsPage(),
        // '/student/review-application-detail': (_) => const StudentReviewApplicationDetailPage(),
        '/student/review-application-detail': (context) {
          final appId = ModalRoute.of(context)!.settings.arguments as String;
          return StudentReviewApplicationDetailPage(appId: appId);
        },
        '/student/apply-peer': (_) => const StudentApplyPeerPage(),
        '/peer/profile': (_) => const PeerProfilePage(),
        '/tutor/students': (_) => const PeerTutorStudentsPage(),
        '/tutor/students/detail': (_) => const PeerTutorStudentDetailPage(),
        '/tutor/pas_paper': (_) => const PeerTutorPastYearRepositoryPage(),
        '/tutor/personal_profile': (_) => const PeerTutorProfilePage(),


        // Peer Tutor & Peer Counsellor (FIXED: leading slash)
        '/peer_tutor/booking': (_) => const PeerBookingInfoPage(),
        '/peer_tutor/home': (_) => const PeerTutorHomePage(),
        '/tutor/scheduling': (_) => const PeerTutorSchedulePage(),

        // HOP (FIXED: leading slash)
        '/hop/home': (_) => const HopHomePage(),
        '/hop/my-tutors': (_) => const HopMyTutorsPage(),
        '/hop/scheduling': (_) => const HopSchedulingPage(),
        '/hop/booking': (_) => const HopBookingInfoPage(),
        '/hop/profile': (_) => const HopProfilePage(),
        '/hop/my-tutors/detail': (_) => const HopTutorDetailPage(),
        '/hop/student-report': (_) => const HopStudentReportPage(),
        '/hop/make-appointment': (_) => const HopMakeAppointmentPage(),
        '/hop/review/view': (context) {
            final appId = ModalRoute.of(context)!.settings.arguments as String;
            return HopReviewApplicationDetailPage(appId: appId);
       },
        // '/hop/my-tutors': (_) => const HopMyTutorsPage(),
        '/hop/review-applications': (_) => const HopReviewApplicationsPage(),

        // Admin (FIXED: leading slash)
        '/admin/home': (_) => const AdminHomePage(),
        '/admin/users': (_) => const AdminUserManagementPage(),
        '/admin/repository': (_) => const PastYearRepositoryPage(),
        '/admin/interests': (_) => const AdminInterestsPage(),
        '/admin/faculty': (_) => const AdminFacultyPage(),
        '/admin/review-applications': (_) => const AdminReviewApplicationsPage(),
        '/admin/review-applications-detail': (context) {
          final appId = ModalRoute.of(context)!.settings.arguments as String;
          return AdminReviewApplicationDetailPage(appId: appId);
        },
        '/admin/reports': (_) => const AdminReviewReportsPage(),

        // School Counsellor
        '/counsellor/home': (_) => const SchoolCounsellorHomePage(),
        '/counsellor/review-apps': (_) => const SchoolCounsellorReviewApplicationsPage(),
        '/school_counsellor/detail_page': (_) => const SchoolCounsellorDetailPage(),
        '/school-counsellor//appointment': (_) => const SchoolCounsellorMakeAppointmentPage(),
        '/school-counsellor/scheduling': (_) => const SchoolCounsellorSchedulingPage(),
        '/counsellor/review/detail': (context) {
          final appId = ModalRoute.of(context)!.settings.arguments as String;
          return SchoolCounsellorApplicationDetailPage(appId: appId);
        },
        '/peer_counsellor/home': (_) => const PeerCounsellorHomePage(),
        '/peer_counsellor/schedule': (_) => const PeerCounsellorSchedulePage(),
        '/counsellor/my-counsellors': (_) => const SchoolCounsellorMyCounsellorsPage(),
        '/school-counsellors/booking-info': (_) => const SchoolCounsellorBookingInfoPage(),
        '/school-counsellors/profile': (_) => const SchoolCounsellorProfilePage(),
        '/counsellor/booking': (_) => const PeerCounsellorBookingInfoPage(),
        '/counsellor/peers': (_) => const PeerCounsellorPeersPage(),
        '/counsellor/peers/detail': (_) => const PeerCounsellorPeerDetailPage(),
        '/counsellor/profile': (_) => const PeerCounsellorProfilePage(),
      },
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(title)),
          body: const Center(child: Text('Coming soon')));
}
