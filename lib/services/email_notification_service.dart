// lib/email_notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EmailNotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Common HTML styles for all emails
  static const String _emailStyles = '''
    <style>
      body { 
        font-family: Arial, sans-serif; 
        line-height: 1.6; 
        color: #333; 
        margin: 0; 
        padding: 0; 
      }
      .container { 
        max-width: 600px; 
        margin: 0 auto; 
        background: white;
      }
      .header { 
        background: linear-gradient(135deg, #B388FF, #7C4DFF); 
        color: white; 
        padding: 30px; 
        text-align: center; 
      }
      .content { 
        padding: 30px; 
        background: #f9f9f9; 
      }
      .info-box { 
        background: white; 
        border-left: 4px solid #7C4DFF; 
        padding: 15px; 
        margin: 20px 0; 
      }
      .success-box {
        background: #e8f5e9;
        border-left: 4px solid #4caf50;
        padding: 15px;
        margin: 20px 0;
      }
      .warning-box {
        background: #fff3cd;
        border-left: 4px solid #ffc107;
        padding: 15px;
        margin: 20px 0;
      }
      .error-box {
        background: #ffebee;
        border-left: 4px solid #f44336;
        padding: 15px;
        margin: 20px 0;
      }
      .button {
        display: inline-block;
        padding: 12px 24px;
        background: #7C4DFF;
        color: white !important;
        text-decoration: none;
        border-radius: 5px;
        margin: 15px 0;
      }
      .footer { 
        text-align: center; 
        padding: 20px; 
        color: #666; 
        font-size: 12px; 
      }
      ul { 
        padding-left: 20px; 
      }
      li { 
        margin: 8px 0; 
      }
      .detail-row {
        margin: 8px 0;
      }
      .detail-label {
        font-weight: bold;
        color: #555;
      }
    </style>
  ''';

  // Helper function to send email
  static Future<void> _sendEmail({
    required String to,
    required String subject,
    required String htmlContent,
  }) async {
    try {
      await _firestore.collection('mail').add({
        'to': to,
        'message': {
          'subject': subject,
          'html': htmlContent,
        },
      });
    } catch (e) {
      debugPrint('Failed to send email: $e');
    }
  }

  // 1. New appointment notification to Peer
  static Future<void> sendNewAppointmentToPeer({
    required String peerEmail,
    required String peerName,
    required String studentName,
    required String studentRole,
    required String appointmentDate,
    required String appointmentTime,
    required String purpose,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>New Appointment Request</h2>
            <p>Dear $peerName,</p>
            <p>You have received a new appointment request from a $studentRole.</p>
            
            <div class="info-box">
              <strong>Appointment Details:</strong>
              <div class="detail-row">
                <span class="detail-label">Requested by:</span> $studentName
              </div>
              <div class="detail-row">
                <span class="detail-label">Role:</span> $studentRole
              </div>
              <div class="detail-row">
                <span class="detail-label">Date:</span> $appointmentDate
              </div>
              <div class="detail-row">
                <span class="detail-label">Time:</span> $appointmentTime
              </div>
              <div class="detail-row">
                <span class="detail-label">Purpose:</span> $purpose
              </div>
            </div>
            
            <div class="warning-box">
              <strong>Action Required:</strong>
              <p style="margin: 10px 0;">Please open the PEERS app to review this request and confirm or decline the appointment.</p>
            </div>
            
            <p>Thank you for being part of the PEERS community.</p>
            <p>Best regards,<br>PEERS System</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email. Use the app to manage your appointments.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: peerEmail,
      subject: 'PEERS: New Appointment Request',
      htmlContent: html,
    );
  }

  // 2. Appointment confirmed notification to Student/HOP/School Counsellor
  static Future<void> sendAppointmentConfirmedToStudent({
    required String studentEmail,
    required String studentName,
    required String peerName,
    required String peerRole,
    required String appointmentDate,
    required String appointmentTime,
    required String purpose,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Appointment Confirmed</h2>
            <p>Dear $studentName,</p>
            <p>Great news! Your appointment has been confirmed.</p>
            
            <div class="success-box">
              <strong>Confirmed Appointment Details:</strong>
              <div class="detail-row">
                <span class="detail-label">With:</span> $peerName ($peerRole)
              </div>
              <div class="detail-row">
                <span class="detail-label">Date:</span> $appointmentDate
              </div>
              <div class="detail-row">
                <span class="detail-label">Time:</span> $appointmentTime
              </div>
              <div class="detail-row">
                <span class="detail-label">Purpose:</span> $purpose
              </div>
            </div>
            
            <div class="info-box">
              <strong>Next Steps:</strong>
              <ul style="margin: 10px 0;">
                <li>Mark this appointment in your calendar</li>
                <li>Prepare any questions or materials you need</li>
                <li>If you need to reschedule, do so at least 24 hours in advance</li>
              </ul>
            </div>
            
            <p>We look forward to your session!</p>
            <p>Best regards,<br>PEERS System</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email. Use the app to manage your appointments.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Appointment Confirmed',
      htmlContent: html,
    );
  }

  static Future<void> sendAppointmentConfirmedToPeer({
    required String peerEmail,
    required String peerName,
    required String studentName,
    required String studentRole,
    required String appointmentDate,
    required String appointmentTime,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Appointment Confirmed</h2>
            <p>Dear $peerName,</p>
            <p>Your rescheduled appointment has been accepted and confirmed.</p>
            
            <div class="success-box">
              <strong>Confirmed Appointment Details:</strong>
              <div class="detail-row">
                <span class="detail-label">With:</span> $studentName ($studentRole)
              </div>
              <div class="detail-row">
                <span class="detail-label">Date:</span> $appointmentDate
              </div>
              <div class="detail-row">
                <span class="detail-label">Time:</span> $appointmentTime
              </div>
            </div>
            
            <div class="info-box">
              <strong>Next Steps:</strong>
              <ul style="margin: 10px 0;">
                <li>Mark this appointment in your calendar</li>
                <li>Please ensure you are on time</li>
              </ul>
            </div>
            
            <p>Best regards,<br>PEERS System</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email. Use the app to manage your appointments.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: peerEmail,
      subject: 'PEERS: Appointment Confirmed',
      htmlContent: html,
    );
  }

  // 3. Reschedule request from Peer to Student
  static Future<void> sendRescheduleRequestToStudent({
    required String studentEmail,
    required String studentName,
    required String peerName,
    required String peerRole,
    required String originalDate,
    required String originalTime,
    required String newDate,
    required String newTime,
    required String reason,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Appointment Reschedule Request</h2>
            <p>Dear $studentName,</p>
            <p>Your $peerRole, $peerName, has requested to reschedule your appointment.</p>
            
            <div class="warning-box">
              <strong>Original Appointment:</strong>
              <div class="detail-row">
                <span class="detail-label">Date:</span> $originalDate
              </div>
              <div class="detail-row">
                <span class="detail-label">Time:</span> $originalTime
              </div>
            </div>
            
            <div class="info-box">
              <strong>Proposed New Time:</strong>
              <div class="detail-row">
                <span class="detail-label">Date:</span> $newDate
              </div>
              <div class="detail-row">
                <span class="detail-label">Time:</span> $newTime
              </div>
              <div class="detail-row">
                <span class="detail-label">Reason:</span> $reason
              </div>
            </div>
            
            <div class="warning-box">
              <strong>Action Required:</strong>
              <p style="margin: 10px 0;">Please open the PEERS app to review and accept or decline this reschedule request.</p>
            </div>
            
            <p>Thank you for your understanding.</p>
            <p>Best regards,<br>PEERS System</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email. Use the app to respond to this request.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Appointment Reschedule Request',
      htmlContent: html,
    );
  }

  // 4. Reschedule request from Student to Peer
  static Future<void> sendRescheduleRequestToPeer({
    required String peerEmail,
    required String peerName,
    required String studentName,
    required String studentRole,
    required String originalDate,
    required String originalTime,
    required String newDate,
    required String newTime,
    required String reason,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Appointment Reschedule Request</h2>
            <p>Dear $peerName,</p>
            <p>$studentName ($studentRole) has requested to reschedule their appointment with you.</p>
            
            <div class="warning-box">
              <strong>Original Appointment:</strong>
              <div class="detail-row">
                <span class="detail-label">Date:</span> $originalDate
              </div>
              <div class="detail-row">
                <span class="detail-label">Time:</span> $originalTime
              </div>
            </div>
            
            <div class="info-box">
              <strong>Proposed New Time:</strong>
              <div class="detail-row">
                <span class="detail-label">Date:</span> $newDate
              </div>
              <div class="detail-row">
                <span class="detail-label">Time:</span> $newTime
              </div>
              <div class="detail-row">
                <span class="detail-label">Reason:</span> $reason
              </div>
            </div>
            
            <div class="warning-box">
              <strong>Action Required:</strong>
              <p style="margin: 10px 0;">Please open the PEERS app to review and accept or decline this reschedule request.</p>
            </div>
            
            <p>Thank you for your flexibility.</p>
            <p>Best regards,<br>PEERS System</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email. Use the app to respond to this request.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: peerEmail,
      subject: 'PEERS: Appointment Reschedule Request',
      htmlContent: html,
    );
  }

  // 5. Cancellation notification from Peer to Student
  static Future<void> sendCancellationToStudent({
    required String studentEmail,
    required String studentName,
    required String peerName,
    required String peerRole,
    required String appointmentDate,
    required String appointmentTime,
    required String reason,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Appointment Cancelled</h2>
            <p>Dear $studentName,</p>
            <p>We regret to inform you that your appointment has been cancelled by your $peerRole.</p>
            
            <div class="error-box">
              <strong>Cancelled Appointment:</strong>
              <div class="detail-row">
                <span class="detail-label">With:</span> $peerName ($peerRole)
              </div>
              <div class="detail-row">
                <span class="detail-label">Date:</span> $appointmentDate
              </div>
              <div class="detail-row">
                <span class="detail-label">Time:</span> $appointmentTime
              </div>
              <div class="detail-row">
                <span class="detail-label">Reason:</span> $reason
              </div>
            </div>
            
            <div class="info-box">
              <strong>What to do next:</strong>
              <ul style="margin: 10px 0;">
                <li>You can reschedule with the same peer through the app</li>
                <li>Or find another available peer tutor/counsellor</li>
              </ul>
            </div>
            
            <p>We apologize for any inconvenience.</p>
            <p>Best regards,<br>PEERS System</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email. Use the app to book a new appointment.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Appointment Cancelled',
      htmlContent: html,
    );
  }

  // 6. Cancellation notification from Student to Peer
  static Future<void> sendCancellationToPeer({
    required String peerEmail,
    required String peerName,
    required String studentName,
    required String studentRole,
    required String appointmentDate,
    required String appointmentTime,
    required String reason,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Appointment Cancelled</h2>
            <p>Dear $peerName,</p>
            <p>Your appointment has been cancelled by the student.</p>
            
            <div class="error-box">
              <strong>Cancelled Appointment:</strong>
              <div class="detail-row">
                <span class="detail-label">With:</span> $studentName ($studentRole)
              </div>
              <div class="detail-row">
                <span class="detail-label">Date:</span> $appointmentDate
              </div>
              <div class="detail-row">
                <span class="detail-label">Time:</span> $appointmentTime
              </div>
              <div class="detail-row">
                <span class="detail-label">Reason:</span> $reason
              </div>
            </div>
            
            <div class="info-box">
              <strong>Note:</strong>
              <p style="margin: 10px 0;">This time slot is now available for other appointments.</p>
            </div>
            
            <p>Thank you for your understanding.</p>
            <p>Best regards,<br>PEERS System</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: peerEmail,
      subject: 'PEERS: Appointment Cancelled',
      htmlContent: html,
    );
  }

  // 7. HOP approval notification to Student
  static Future<void> sendHopApprovalToStudent({
    required String studentEmail,
    required String studentName,
    required String roleAppliedFor,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Application Approved by HOP</h2>
            <p>Dear $studentName,</p>
            <p>Congratulations! Your application to become a $roleAppliedFor has been approved by the Head of Programme (HOP).</p>
            
            <div class="success-box">
              <strong>Application Status:</strong>
              <div class="detail-row">
                <span class="detail-label">Role Applied For:</span> $roleAppliedFor
              </div>
              <div class="detail-row">
                <span class="detail-label">HOP Review:</span> <span style="color: #4caf50;">Approved</span>
              </div>
              <div class="detail-row">
                <span class="detail-label">Next Step:</span> Admin Review Pending
              </div>
            </div>
            
            <div class="info-box">
              <strong>What's Next:</strong>
              <p style="margin: 10px 0;">Your application is now pending final approval from the admin team. You will receive another email once the admin makes their decision.</p>
            </div>
            
            <p>Thank you for your patience!</p>
            <p>Best regards,<br>PEERS Admin Team</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Application Approved by HOP',
      htmlContent: html,
    );
  }

  // 8. HOP rejection notification to Student
  static Future<void> sendHopRejectionToStudent({
    required String studentEmail,
    required String studentName,
    required String roleAppliedFor,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Application Update</h2>
            <p>Dear $studentName,</p>
            <p>Thank you for your interest in becoming a $roleAppliedFor in the PEERS program.</p>
            
            <div class="error-box">
              <strong>Application Status:</strong>
              <div class="detail-row">
                <span class="detail-label">Role Applied For:</span> $roleAppliedFor
              </div>
              <div class="detail-row">
                <span class="detail-label">HOP Review:</span> <span style="color: #f44336;">Not Approved</span>
              </div>
            </div>
            
            <div class="info-box">
              <strong>What This Means:</strong>
              <p style="margin: 10px 0;">Unfortunately, your application was not approved at this time. We encourage you to:</p>
              <ul style="margin: 10px 0;">
                <li>Consider reapplying in the future</li>
                <li>Gain more experience in peer support</li>
                <li>Contact your HOP for feedback</li>
              </ul>
            </div>
            
            <p>We appreciate your interest in supporting your peers and hope you'll consider applying again in the future.</p>
            <p>Best regards,<br>PEERS Admin Team</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Application Update',
      htmlContent: html,
    );
  }

  // 9. School Counsellor approval notification to Student
  static Future<void> sendSchoolCounsellorApprovalToStudent({
    required String studentEmail,
    required String studentName,
    required String roleAppliedFor,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Application Approved by School Counsellor</h2>
            <p>Dear $studentName,</p>
            <p>Great news! Your application to become a $roleAppliedFor has been approved by the School Counsellor.</p>
            
            <div class="success-box">
              <strong>Application Status:</strong>
              <div class="detail-row">
                <span class="detail-label">Role Applied For:</span> $roleAppliedFor
              </div>
              <div class="detail-row">
                <span class="detail-label">School Counsellor Review:</span> <span style="color: #4caf50;">Approved</span>
              </div>
              <div class="detail-row">
                <span class="detail-label">Next Step:</span> Admin Review Pending
              </div>
            </div>
            
            <div class="info-box">
              <strong>What's Next:</strong>
              <p style="margin: 10px 0;">Your application is now pending final approval from the admin team. You will receive another email once the admin makes their decision.</p>
            </div>
            
            <p>Thank you for your commitment to helping your peers!</p>
            <p>Best regards,<br>PEERS Admin Team</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Application Approved by School Counsellor',
      htmlContent: html,
    );
  }

  // 10. School Counsellor rejection notification to Student
  static Future<void> sendSchoolCounsellorRejectionToStudent({
    required String studentEmail,
    required String studentName,
    required String roleAppliedFor,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Application Update</h2>
            <p>Dear $studentName,</p>
            <p>Thank you for your interest in becoming a $roleAppliedFor in the PEERS program.</p>
            
            <div class="error-box">
              <strong>Application Status:</strong>
              <div class="detail-row">
                <span class="detail-label">Role Applied For:</span> $roleAppliedFor
              </div>
              <div class="detail-row">
                <span class="detail-label">School Counsellor Review:</span> <span style="color: #f44336;">Not Approved</span>
              </div>
            </div>
            
            <div class="info-box">
              <strong>What This Means:</strong>
              <p style="margin: 10px 0;">Unfortunately, your application was not approved at this time. We encourage you to:</p>
              <ul style="margin: 10px 0;">
                <li>Consider reapplying in the future</li>
                <li>Develop your counselling skills further</li>
                <li>Contact the School Counsellor for feedback</li>
              </ul>
            </div>
            
            <p>We appreciate your dedication to supporting your peers and hope you'll consider applying again in the future.</p>
            <p>Best regards,<br>PEERS Admin Team</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Application Update',
      htmlContent: html,
    );
  }

  // 11. Admin approval notification to Student
  static Future<void> sendAdminApprovalToStudent({
    required String studentEmail,
    required String studentName,
    required String roleAppliedFor,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Application Approved - Welcome to PEERS!</h2>
            <p>Dear $studentName,</p>
            <p>Congratulations! We are thrilled to inform you that your application to become a $roleAppliedFor has been approved by the admin team.</p>
            
            <div class="success-box">
              <strong>Application Status:</strong>
              <div class="detail-row">
                <span class="detail-label">Role Applied For:</span> $roleAppliedFor
              </div>
              <div class="detail-row">
                <span class="detail-label">Admin Review:</span> <span style="color: #4caf50;">Approved</span>
              </div>
              <div class="detail-row">
                <span class="detail-label">Status:</span> <span style="color: #4caf50;">Active</span>
              </div>
            </div>
            
            <div class="info-box">
              <strong>What's Next:</strong>
              <ul style="margin: 10px 0;">
                <li>Your account has been updated with your new role</li>
                <li>You can now log in and access $roleAppliedFor features</li>
                <li>Start accepting appointments from students</li>
                <li>Check your schedule regularly</li>
              </ul>
            </div>
            
            <p>Welcome to the PEERS team! We're excited to have you on board.</p>
            <p>Best regards,<br>PEERS Admin Team</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Application Approved - Welcome!',
      htmlContent: html,
    );
  }

  // 12. Admin rejection notification to Student
  static Future<void> sendAdminRejectionToStudent({
    required String studentEmail,
    required String studentName,
    required String roleAppliedFor,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Application Decision</h2>
            <p>Dear $studentName,</p>
            <p>Thank you for your interest in becoming a $roleAppliedFor in the PEERS program.</p>
            
            <div class="error-box">
              <strong>Application Status:</strong>
              <div class="detail-row">
                <span class="detail-label">Role Applied For:</span> $roleAppliedFor
              </div>
              <div class="detail-row">
                <span class="detail-label">Admin Review:</span> <span style="color: #f44336;">Not Approved</span>
              </div>
            </div>
            
            <div class="info-box">
              <strong>What This Means:</strong>
              <p style="margin: 10px 0;">After careful review, your application was not approved at this time. This decision could be due to various factors including:</p>
              <ul style="margin: 10px 0;">
                <li>Current capacity of peer tutors/counsellors</li>
                <li>Specific program requirements</li>
                <li>Application completeness</li>
              </ul>
            </div>
            
            <div class="info-box">
              <strong>Next Steps:</strong>
              <ul style="margin: 10px 0;">
                <li>You can reapply in the future</li>
                <li>Contact admin for feedback: admin@gmail.com</li>
                <li>Continue developing your skills and experience</li>
              </ul>
            </div>
            
            <p>We appreciate your interest in supporting your fellow students and encourage you to apply again in the future.</p>
            <p>Best regards,<br>PEERS Admin Team</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email. Contact admin@gmail.com for questions.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Application Decision',
      htmlContent: html,
    );
  }

  // 13. Removed from peer group notification
  static Future<void> sendRemovedFromPeerGroupToStudent({
    required String studentEmail,
    required String studentName,
    required String peerRole,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>$_emailStyles</head>
      <body>
        <div class="container">
          <div class="header">
            <h1>PEERS</h1>
          </div>
          <div class="content">
            <h2>Role Update Notification</h2>
            <p>Dear $studentName,</p>
            <p>We're writing to inform you that your role as a $peerRole has been updated in the PEERS system.</p>
            
            <div class="warning-box">
              <strong>Role Change:</strong>
              <div class="detail-row">
                <span class="detail-label">Previous Role:</span> $peerRole
              </div>
              <div class="detail-row">
                <span class="detail-label">New Role:</span> Student
              </div>
              <div class="detail-row">
                <span class="detail-label">Changed By:</span> Admin/HOP/School Counsellor
              </div>
            </div>
            
            <div class="info-box">
              <strong>What This Means:</strong>
              <ul style="margin: 10px 0;">
                <li>You no longer have $peerRole permissions</li>
                <li>Your account has been reverted to Student role</li>
                <li>All your scheduled appointments as $peerRole have been cancelled</li>
                <li>You can still access PEERS as a student</li>
              </ul>
            </div>
            
            <div class="info-box">
              <strong>Questions?</strong>
              <p style="margin: 10px 0;">If you have questions about this change, please contact:</p>
              <ul style="margin: 10px 0;">
                <li>Email: admin@gmail.com</li>
                <li>Visit: IT Services @ Level 3</li>
              </ul>
            </div>
            
            <p>Thank you for your contributions to the PEERS community.</p>
            <p>Best regards,<br>PEERS Admin Team</p>
          </div>
          <div class="footer">
            <p>This is an automated message from PEERS.</p>
            <p>Please do not reply to this email. Contact support using the details above.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    await _sendEmail(
      to: studentEmail,
      subject: 'PEERS: Role Update Notification',
      htmlContent: html,
    );
  }
}