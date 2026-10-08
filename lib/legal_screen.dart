import 'package:flutter/material.dart';

import 'app_ui.dart';

// ===========================================================================
// IMPORTANT - READ BEFORE SHIPPING
//
// This is a working TEMPLATE written to fit what PlantGuard actually does:
// it collects an email, a username, and sensor readings from IoT devices, and
// stores them in Google Firebase. It is written to be honest and specific
// rather than generic filler, and it references the Philippines Data Privacy
// Act of 2012 (RA 10173) because that is the jurisdiction it will be used in.
//
// It is NOT legal advice, and I am not a lawyer. Before any public release -
// and certainly before a defence or deployment - have someone qualified read
// it, and update the placeholders marked CHANGE ME below.
// ===========================================================================

/// CHANGE ME - your details, used throughout both documents.
const String kCompanyName = 'PlantGuard';
const String kContactEmail = 'rjq.dev@gmail.com';
const String kJurisdiction = 'the Republic of the Philippines';
const String kLastUpdated = '9 September 2025';

enum LegalDoc { terms, privacy }

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  static Route<void> route(LegalDoc doc) =>
      slideSideRoute<void>(LegalScreen(doc: doc));

  String get _title =>
      doc == LegalDoc.terms ? 'Terms and Conditions' : 'Privacy Policy';

  List<_Section> get _sections =>
      doc == LegalDoc.terms ? _termsSections : _privacySections;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final double w = size.width;
    final double sideMargin = AppMetrics.s(w, 16);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1E0D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackground(),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: sideMargin),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: AppMetrics.s(w, 8)),
                  BackCircleButton(
                    screenW: w,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(height: AppMetrics.s(w, 14)),

                  Text(
                    _title,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppMetrics.s(w, 24),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                          color: Color(0x59000000),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: AppMetrics.s(w, 4)),
                  Text(
                    'Last updated $kLastUpdated',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppMetrics.s(w, 11),
                      color: AppColors.hint,
                    ),
                  ),
                  SizedBox(height: AppMetrics.s(w, 16)),

                  Expanded(child: _body(w)),
                  SizedBox(height: sideMargin),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(double w) {
    return GlassCard(
      screenW: w,
      padded: false,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          AppMetrics.s(w, 22),
          AppMetrics.s(w, 22),
          AppMetrics.s(w, 22),
          AppMetrics.s(w, 28),
        ),
        itemCount: _sections.length,
        itemBuilder: (BuildContext context, int i) {
          final _Section s = _sections[i];
          return Padding(
            padding: EdgeInsets.only(bottom: AppMetrics.s(w, 22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ${s.heading}',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppMetrics.s(w, 14),
                    fontWeight: FontWeight.w700,
                    color: AppColors.wordmarkGreen,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: AppMetrics.s(w, 7)),
                for (final String p in s.paragraphs)
                  Padding(
                    padding: EdgeInsets.only(bottom: AppMetrics.s(w, 8)),
                    child: Text(
                      p,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppMetrics.s(w, 12),
                        color: AppColors.bodyText,
                        height: 1.55,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Section {
  const _Section(this.heading, this.paragraphs);
  final String heading;
  final List<String> paragraphs;
}

// ===========================================================================
// TERMS AND CONDITIONS
// ===========================================================================

const List<_Section> _termsSections = <_Section>[
  _Section('Acceptance of these terms', <String>[
    'By creating a $kCompanyName account or using the app, you agree to these '
        'Terms and Conditions and to our Privacy Policy. If you do not agree, '
        'please do not create an account or use the service.',
    'You must be at least 13 years old to use $kCompanyName. If you are under '
        '18, you should have a parent or guardian review these terms with you.',
  ]),
  _Section('Your account', <String>[
    'You are responsible for keeping your password confidential and for all '
        'activity that happens under your account. Choose a password you do '
        'not use anywhere else.',
    'Provide accurate information when you register. Accounts created with '
        'someone else\'s email address may be removed.',
    'Tell us promptly at $kContactEmail if you believe someone has gained '
        'access to your account.',
  ]),
  _Section('What the service does', <String>[
    '$kCompanyName connects to IoT sensors to report conditions around your '
        'plants - such as soil moisture, temperature, humidity and light - and '
        'offers guidance based on those readings.',
    'The guidance is informational. It is generated from sensor data and '
        'general horticultural rules, and it does not account for every '
        'variable affecting a living plant.',
  ]),
  _Section('No guarantee of plant health', <String>[
    'We do not guarantee any particular outcome for your plants. Sensors can '
        'fail, drift out of calibration, lose power or lose connectivity, and '
        'readings may be delayed, missing or wrong.',
    'Do not rely on $kCompanyName as the sole basis for decisions about '
        'valuable, rare or commercially important plants. Use your own '
        'judgement and inspect your plants directly.',
  ]),
  _Section('Acceptable use', <String>[
    'Do not use the service to break any law, to interfere with or overload '
        'our systems, to attempt unauthorised access to any account or device, '
        'or to reverse engineer the app except where that right cannot legally '
        'be excluded.',
    'Do not upload content that infringes anyone else\'s rights.',
  ]),
  _Section('Your devices', <String>[
    'You are responsible for the IoT hardware you connect, including its '
        'installation, power supply, network connection and physical safety.',
    'Follow the manufacturer\'s instructions for any sensor or controller you '
        'use with the service, particularly around water and mains electricity.',
  ]),
  _Section('Availability', <String>[
    'We aim to keep the service running but do not promise uninterrupted '
        'availability. It may be unavailable during maintenance, or because of '
        'failures in networks or third-party services we depend on.',
    'We may change, suspend or discontinue features at any time.',
  ]),
  _Section('Limitation of liability', <String>[
    'To the fullest extent permitted by law, $kCompanyName is not liable for '
        'indirect or consequential loss, or for loss of or damage to plants, '
        'crops, equipment or property arising from use of the service or from '
        'reliance on its readings or guidance.',
    'Nothing in these terms excludes liability that cannot lawfully be '
        'excluded.',
  ]),
  _Section('Ending your account', <String>[
    'You may delete your account at any time from within the app or by '
        'writing to $kContactEmail.',
    'We may suspend or end an account that breaches these terms, ordinarily '
        'with notice where it is reasonable to give it.',
  ]),
  _Section('Changes to these terms', <String>[
    'We may update these terms. If a change is significant we will tell you '
        'in the app or by email before it takes effect. Continuing to use the '
        'service after that means you accept the updated terms.',
  ]),
  _Section('Governing law', <String>[
    'These terms are governed by the laws of $kJurisdiction, and disputes are '
        'subject to the exclusive jurisdiction of its courts.',
  ]),
  _Section('Contact', <String>[
    'Questions about these terms: $kContactEmail',
  ]),
];

// ===========================================================================
// PRIVACY POLICY
// ===========================================================================

const List<_Section> _privacySections = <_Section>[
  _Section('Overview', <String>[
    'This policy explains what $kCompanyName collects, why, and what you can '
        'do about it. We collect only what the service needs to work.',
    'We handle personal information in line with the Data Privacy Act of 2012 '
        '(Republic Act No. 10173) and its implementing rules.',
  ]),
  _Section('What we collect', <String>[
    'Account information: your email address, your chosen username, and a '
        'securely hashed form of your password. We never see or store your '
        'password in readable form.',
    'Sensor data: readings sent by IoT devices you connect - such as soil '
        'moisture, temperature, humidity and light - along with the device '
        'identifier and the time of each reading.',
    'Technical information: basic app and device details needed to deliver '
        'the service and diagnose faults, such as app version and error logs.',
    'We do not collect your precise location, contacts, photos or files.',
  ]),
  _Section('Why we collect it', <String>[
    'To create and secure your account, and to sign you in.',
    'To show your plants\' readings and history, and to generate care '
        'guidance from them.',
    'To send account emails, such as the verification code used when you '
        'register.',
    'To find and fix faults, and to keep the service secure.',
  ]),
  _Section('Where your data is stored', <String>[
    'Account and sensor data are stored using Google Firebase (Firebase '
        'Authentication and Cloud Firestore), operated by Google LLC. Data may '
        'therefore be processed on servers outside the Philippines.',
    'Verification emails are sent using EmailJS. Only your email address, '
        'your username and the one-time code are shared with that service, '
        'purely to deliver the message.',
    'We do not sell your personal information, and we do not share it with '
        'advertisers.',
  ]),
  _Section('How long we keep it', <String>[
    'Account information is kept while your account is open.',
    'Sensor readings are kept so you can see history over time. You may ask '
        'us to delete them at any point.',
    'When you delete your account we remove your account information and '
        'associated readings, other than anything we must keep to meet a legal '
        'obligation.',
    'Verification codes are held only in the app\'s memory and expire after '
        '15 minutes. They are never written to our database.',
  ]),
  _Section('Your rights', <String>[
    'Under the Data Privacy Act you have the right to be informed, to access '
        'your data, to correct it, to object to processing, to have it erased '
        'or blocked, to data portability, and to damages for a violation of '
        'your rights.',
    'To exercise any of these, write to $kContactEmail. We will respond '
        'within a reasonable period.',
    'You may also complain to the National Privacy Commission at '
        'privacy.gov.ph.',
  ]),
  _Section('Security', <String>[
    'Connections between the app and our servers are encrypted in transit. '
        'Access to stored data is restricted so that your records are readable '
        'only by your signed-in account.',
    'No system is perfectly secure. If a breach occurs that is likely to put '
        'your rights at risk, we will notify you and the National Privacy '
        'Commission as the law requires.',
  ]),
  _Section('Children', <String>[
    '$kCompanyName is not directed at children under 13. If we learn we have '
        'collected information from a child under 13 without proper consent, '
        'we will delete it.',
  ]),
  _Section('Changes to this policy', <String>[
    'We may update this policy. Significant changes will be announced in the '
        'app or by email before they take effect, and the date at the top of '
        'this page will change.',
  ]),
  _Section('Contact', <String>[
    'Questions, requests or complaints about your data: $kContactEmail',
  ]),
];
