import 'package:flutter/material.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool showNotifications = false;
  bool showIconBadges = true;
  bool floatingNotifications = true;
  bool lockScreenNotifications = true;
  bool allowSound = true;
  bool allowVibration = true;

  @override
  Widget build(BuildContext context) {
    // Scaling factor
    final double scale = 0.8;
    final Size screen = MediaQuery.of(context).size;
    final double cardWidth = screen.width * scale;
    final double cardHeight = (screen.height - 40) * scale;
    final double cardRadius = 36 * scale;
    final double headerHeight = 90 * scale;
    final double cardPadding = 32 * scale;
    final double iconSize = 28 * scale;
    final double dividerThickness = 1 * scale;
    final double switchScale = scale;
    final double titleFontSize = 26 * scale;
    final double saveFontSize = 20 * scale;
    final double labelFontSize = 20 * scale;
    final double subLabelFontSize = 14 * scale;
    final double spacingLarge = 32 * scale;
    final double spacingMedium = 18 * scale;
    final double spacingSmall = 8 * scale;
    final double spacingTiny = 2 * scale;
    final double spacingBottom = 24 * scale;
    final Color backgroundColor = const Color(0xFFFDE7EF);
    final Color cardColor = const Color(0xFFFEF7F0);
    final Color headerGradientStart = const Color(0xFFE7BBAA);
    final Color headerGradientEnd = const Color(0x00E7BBAA);
    final Color dividerColor = const Color(0xFFF3CFC1);
    final Color subTextColor = const Color(0xFF8B7B9B);
    final Color toggleActiveColor = const Color(0xFF7BB6FF);
    final Color toggleInactiveColor = const Color(0xFFBDBDBD);
    final Color iconColor = Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                image: const DecorationImage(
                  image: AssetImage('assets/background.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // Centered notification card
          Center(
            child: Container(
              width: cardWidth,
              height: cardHeight,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(cardRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    height: headerHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(cardRadius),
                        topRight: Radius.circular(cardRadius),
                      ),
                      gradient: LinearGradient(
                        colors: [headerGradientStart, headerGradientEnd],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            icon: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: iconColor,
                              size: iconSize,
                            ),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                        Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 16 * scale),
                            child: Text(
                              'Notification Settings',
                              style: TextStyle(
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                                fontFamily: 'Montserrat',
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 24 * scale,
                          bottom: 28 * scale,
                          child: Text(
                            'Save',
                            style: TextStyle(
                              fontSize: saveFontSize,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Settings
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: cardPadding),
                      child: ListView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: spacingLarge),
                          // Show notifications
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Show notifications',
                                style: TextStyle(
                                  fontSize: labelFontSize,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              Transform.scale(
                                scale: switchScale,
                                child: Switch(
                                  value: showNotifications,
                                  onChanged: (val) {
                                    setState(() => showNotifications = val);
                                  },
                                  activeColor: toggleActiveColor,
                                  inactiveThumbColor: toggleInactiveColor,
                                  inactiveTrackColor: toggleInactiveColor
                                      .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacingMedium),
                          Divider(
                            color: dividerColor,
                            thickness: dividerThickness,
                          ),
                          SizedBox(height: spacingMedium),
                          // Show icon badges
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Show icon badges',
                                style: TextStyle(
                                  fontSize: labelFontSize,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              Transform.scale(
                                scale: switchScale,
                                child: Switch(
                                  value: showIconBadges,
                                  onChanged: (val) {
                                    setState(() => showIconBadges = val);
                                  },
                                  activeColor: toggleActiveColor,
                                  inactiveThumbColor: toggleInactiveColor,
                                  inactiveTrackColor: toggleInactiveColor
                                      .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacingSmall),
                          // Floating notifications
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Floating notifications',
                                    style: TextStyle(
                                      fontSize: labelFontSize,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  SizedBox(height: spacingTiny),
                                  Text(
                                    'Allow notifications on the Lock screen',
                                    style: TextStyle(
                                      fontSize: subLabelFontSize,
                                      color: subTextColor,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ],
                              ),
                              Transform.scale(
                                scale: switchScale,
                                child: Switch(
                                  value: floatingNotifications,
                                  onChanged: (val) {
                                    setState(() => floatingNotifications = val);
                                  },
                                  activeColor: toggleActiveColor,
                                  inactiveThumbColor: toggleInactiveColor,
                                  inactiveTrackColor: toggleInactiveColor
                                      .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacingSmall),
                          // Lock screen notifications
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Lock screen notifications',
                                    style: TextStyle(
                                      fontSize: labelFontSize,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  SizedBox(height: spacingTiny),
                                  Text(
                                    'Allow notifications on the Lock screen',
                                    style: TextStyle(
                                      fontSize: subLabelFontSize,
                                      color: subTextColor,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ],
                              ),
                              Transform.scale(
                                scale: switchScale,
                                child: Switch(
                                  value: lockScreenNotifications,
                                  onChanged: (val) {
                                    setState(
                                      () => lockScreenNotifications = val,
                                    );
                                  },
                                  activeColor: toggleActiveColor,
                                  inactiveThumbColor: toggleInactiveColor,
                                  inactiveTrackColor: toggleInactiveColor
                                      .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacingSmall),
                          // Allow sound
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Allow sound',
                                style: TextStyle(
                                  fontSize: labelFontSize,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              Transform.scale(
                                scale: switchScale,
                                child: Switch(
                                  value: allowSound,
                                  onChanged: (val) {
                                    setState(() => allowSound = val);
                                  },
                                  activeColor: toggleActiveColor,
                                  inactiveThumbColor: toggleInactiveColor,
                                  inactiveTrackColor: toggleInactiveColor
                                      .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacingSmall),
                          // Allow vibration
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Allow vibration',
                                style: TextStyle(
                                  fontSize: labelFontSize,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              Transform.scale(
                                scale: switchScale,
                                child: Switch(
                                  value: allowVibration,
                                  onChanged: (val) {
                                    setState(() => allowVibration = val);
                                  },
                                  activeColor: toggleActiveColor,
                                  inactiveThumbColor: toggleInactiveColor,
                                  inactiveTrackColor: toggleInactiveColor
                                      .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacingBottom),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
