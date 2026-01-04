import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'custom_snackbar.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const double scale = 0.75;
  // Controllers for editable fields
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();

  // Dropdown values
  String? _ageGroup;
  String? _country;
  String? _countryCode;
  final List<Map<String, String>> _ageGroups = [
    {'label': '🧒 Teenagers(13-17)', 'value': 'Teenagers(13-17)'},
    {'label': '🧑 Young adults(18-24)', 'value': 'Young adults(18-24)'},
    {'label': '🧔 Adults(25-34)', 'value': 'Adults(25-34)'},
    {'label': '👨‍🦳 Mid-aged(35-54)', 'value': 'Mid-aged(35-54)'},
    {'label': '👴 Seniors(55 & above)', 'value': 'Seniors(55 & above)'},
  ];
  final List<Map<String, String>> _countries = [
  {'name': 'Afghanistan', 'code': '+93', 'flag': '🇦🇫'},
  {'name': 'Albania', 'code': '+355', 'flag': '🇦🇱'},
  {'name': 'Algeria', 'code': '+213', 'flag': '🇩🇿'},
  {'name': 'Andorra', 'code': '+376', 'flag': '🇦🇩'},
  {'name': 'Angola', 'code': '+244', 'flag': '🇦🇴'},
  {'name': 'Argentina', 'code': '+54', 'flag': '🇦🇷'},
  {'name': 'Armenia', 'code': '+374', 'flag': '🇦🇲'},
  {'name': 'Australia', 'code': '+61', 'flag': '🇦🇺'},
  {'name': 'Austria', 'code': '+43', 'flag': '🇦🇹'},
  {'name': 'Azerbaijan', 'code': '+994', 'flag': '🇦🇿'},
  {'name': 'Bahamas', 'code': '+1-242', 'flag': '🇧🇸'},
  {'name': 'Bahrain', 'code': '+973', 'flag': '🇧🇭'},
  {'name': 'Bangladesh', 'code': '+880', 'flag': '🇧🇩'},
  {'name': 'Barbados', 'code': '+1-246', 'flag': '🇧🇧'},
  {'name': 'Belarus', 'code': '+375', 'flag': '🇧🇾'},
  {'name': 'Belgium', 'code': '+32', 'flag': '🇧🇪'},
  {'name': 'Belize', 'code': '+501', 'flag': '🇧🇿'},
  {'name': 'Benin', 'code': '+229', 'flag': '🇧🇯'},
  {'name': 'Bhutan', 'code': '+975', 'flag': '🇧🇹'},
  {'name': 'Bolivia', 'code': '+591', 'flag': '🇧🇴'},
  {'name': 'Bosnia and Herzegovina', 'code': '+387', 'flag': '🇧🇦'},
  {'name': 'Botswana', 'code': '+267', 'flag': '🇧🇼'},
  {'name': 'Brazil', 'code': '+55', 'flag': '🇧🇷'},
  {'name': 'Brunei', 'code': '+673', 'flag': '🇧🇳'},
  {'name': 'Bulgaria', 'code': '+359', 'flag': '🇧🇬'},
  {'name': 'Burkina Faso', 'code': '+226', 'flag': '🇧🇫'},
  {'name': 'Burundi', 'code': '+257', 'flag': '🇧🇮'},
  {'name': 'Cambodia', 'code': '+855', 'flag': '🇰🇭'},
  {'name': 'Cameroon', 'code': '+237', 'flag': '🇨🇲'},
  {'name': 'Canada', 'code': '+1', 'flag': '🇨🇦'},
  {'name': 'Cape Verde', 'code': '+238', 'flag': '🇨🇻'},
  {'name': 'Central African Republic', 'code': '+236', 'flag': '🇨🇫'},
  {'name': 'Chad', 'code': '+235', 'flag': '🇹🇩'},
  {'name': 'Chile', 'code': '+56', 'flag': '🇨🇱'},
  {'name': 'China', 'code': '+86', 'flag': '🇨🇳'},
  {'name': 'Colombia', 'code': '+57', 'flag': '🇨🇴'},
  {'name': 'Comoros', 'code': '+269', 'flag': '🇰🇲'},
  {'name': 'Congo', 'code': '+242', 'flag': '🇨🇬'},
  {'name': 'Costa Rica', 'code': '+506', 'flag': '🇨🇷'},
  {'name': 'Croatia', 'code': '+385', 'flag': '🇭🇷'},
  {'name': 'Cuba', 'code': '+53', 'flag': '🇨🇺'},
  {'name': 'Cyprus', 'code': '+357', 'flag': '🇨🇾'},
  {'name': 'Czech Republic', 'code': '+420', 'flag': '🇨🇿'},
  {'name': 'Denmark', 'code': '+45', 'flag': '🇩🇰'},
  {'name': 'Djibouti', 'code': '+253', 'flag': '🇩🇯'},
  {'name': 'Dominica', 'code': '+1-767', 'flag': '🇩🇲'},
  {'name': 'Dominican Republic', 'code': '+1-809', 'flag': '🇩🇴'},
  {'name': 'Ecuador', 'code': '+593', 'flag': '🇪🇨'},
  {'name': 'Egypt', 'code': '+20', 'flag': '🇪🇬'},
  {'name': 'El Salvador', 'code': '+503', 'flag': '🇸🇻'},
  {'name': 'Equatorial Guinea', 'code': '+240', 'flag': '🇬🇶'},
  {'name': 'Eritrea', 'code': '+291', 'flag': '🇪🇷'},
  {'name': 'Estonia', 'code': '+372', 'flag': '🇪🇪'},
  {'name': 'Eswatini', 'code': '+268', 'flag': '🇸🇿'},
  {'name': 'Ethiopia', 'code': '+251', 'flag': '🇪🇹'},
  {'name': 'Fiji', 'code': '+679', 'flag': '🇫🇯'},
  {'name': 'Finland', 'code': '+358', 'flag': '🇫🇮'},
  {'name': 'France', 'code': '+33', 'flag': '🇫🇷'},
  {'name': 'Gabon', 'code': '+241', 'flag': '🇬🇦'},
  {'name': 'Gambia', 'code': '+220', 'flag': '🇬🇲'},
  {'name': 'Georgia', 'code': '+995', 'flag': '🇬🇪'},
  {'name': 'Germany', 'code': '+49', 'flag': '🇩🇪'},
  {'name': 'Ghana', 'code': '+233', 'flag': '🇬🇭'},
  {'name': 'Greece', 'code': '+30', 'flag': '🇬🇷'},
  {'name': 'Grenada', 'code': '+1-473', 'flag': '🇬🇩'},
  {'name': 'Guatemala', 'code': '+502', 'flag': '🇬🇹'},
  {'name': 'Guinea', 'code': '+224', 'flag': '🇬🇳'},
  {'name': 'Guinea-Bissau', 'code': '+245', 'flag': '🇬🇼'},
  {'name': 'Guyana', 'code': '+592', 'flag': '🇬🇾'},
  {'name': 'Haiti', 'code': '+509', 'flag': '🇭🇹'},
  {'name': 'Honduras', 'code': '+504', 'flag': '🇭🇳'},
  {'name': 'Hungary', 'code': '+36', 'flag': '🇭🇺'},
  {'name': 'Iceland', 'code': '+354', 'flag': '🇮🇸'},
  {'name': 'India', 'code': '+91', 'flag': '🇮🇳'},
  {'name': 'Indonesia', 'code': '+62', 'flag': '🇮🇩'},
  {'name': 'Iran', 'code': '+98', 'flag': '🇮🇷'},
  {'name': 'Iraq', 'code': '+964', 'flag': '🇮🇶'},
  {'name': 'Ireland', 'code': '+353', 'flag': '🇮🇪'},
  {'name': 'Israel', 'code': '+972', 'flag': '🇮🇱'},
  {'name': 'Italy', 'code': '+39', 'flag': '🇮🇹'},
  {'name': 'Jamaica', 'code': '+1-876', 'flag': '🇯🇲'},
  {'name': 'Japan', 'code': '+81', 'flag': '🇯🇵'},
  {'name': 'Jordan', 'code': '+962', 'flag': '🇯🇴'},
  {'name': 'Kazakhstan', 'code': '+7', 'flag': '🇰🇿'},
  {'name': 'Kenya', 'code': '+254', 'flag': '🇰🇪'},
  {'name': 'Kiribati', 'code': '+686', 'flag': '🇰🇮'},
  {'name': 'Kuwait', 'code': '+965', 'flag': '🇰🇼'},
  {'name': 'Kyrgyzstan', 'code': '+996', 'flag': '🇰🇬'},
  {'name': 'Laos', 'code': '+856', 'flag': '🇱🇦'},
  {'name': 'Latvia', 'code': '+371', 'flag': '🇱🇻'},
  {'name': 'Lebanon', 'code': '+961', 'flag': '🇱🇧'},
  {'name': 'Lesotho', 'code': '+266', 'flag': '🇱🇸'},
  {'name': 'Liberia', 'code': '+231', 'flag': '🇱🇷'},
  {'name': 'Libya', 'code': '+218', 'flag': '🇱🇾'},
  {'name': 'Liechtenstein', 'code': '+423', 'flag': '🇱🇮'},
  {'name': 'Lithuania', 'code': '+370', 'flag': '🇱🇹'},
  {'name': 'Luxembourg', 'code': '+352', 'flag': '🇱🇺'},
  {'name': 'Madagascar', 'code': '+261', 'flag': '🇲🇬'},
  {'name': 'Malawi', 'code': '+265', 'flag': '🇲🇼'},
  {'name': 'Malaysia', 'code': '+60', 'flag': '🇲🇾'},
  {'name': 'Maldives', 'code': '+960', 'flag': '🇲🇻'},
  {'name': 'Mali', 'code': '+223', 'flag': '🇲🇱'},
  {'name': 'Malta', 'code': '+356', 'flag': '🇲🇹'},
  {'name': 'Marshall Islands', 'code': '+692', 'flag': '🇲🇭'},
  {'name': 'Mauritania', 'code': '+222', 'flag': '🇲🇷'},
  {'name': 'Mauritius', 'code': '+230', 'flag': '🇲🇺'},
  {'name': 'Mexico', 'code': '+52', 'flag': '🇲🇽'},
  {'name': 'Micronesia', 'code': '+691', 'flag': '🇫🇲'},
  {'name': 'Moldova', 'code': '+373', 'flag': '🇲🇩'},
  {'name': 'Monaco', 'code': '+377', 'flag': '🇲🇨'},
  {'name': 'Mongolia', 'code': '+976', 'flag': '🇲🇳'},
  {'name': 'Montenegro', 'code': '+382', 'flag': '🇲🇪'},
  {'name': 'Morocco', 'code': '+212', 'flag': '🇲🇦'},
  {'name': 'Mozambique', 'code': '+258', 'flag': '🇲🇿'},
  {'name': 'Myanmar', 'code': '+95', 'flag': '🇲🇲'},
  {'name': 'Namibia', 'code': '+264', 'flag': '🇳🇦'},
  {'name': 'Nauru', 'code': '+674', 'flag': '🇳🇷'},
  {'name': 'Nepal', 'code': '+977', 'flag': '🇳🇵'},
  {'name': 'Netherlands', 'code': '+31', 'flag': '🇳🇱'},
  {'name': 'New Zealand', 'code': '+64', 'flag': '🇳🇿'},
  {'name': 'Nicaragua', 'code': '+505', 'flag': '🇳🇮'},
  {'name': 'Niger', 'code': '+227', 'flag': '🇳🇪'},
  {'name': 'Nigeria', 'code': '+234', 'flag': '🇳🇬'},
  {'name': 'North Korea', 'code': '+850', 'flag': '🇰🇵'},
  {'name': 'North Macedonia', 'code': '+389', 'flag': '🇲🇰'},
  {'name': 'Norway', 'code': '+47', 'flag': '🇳🇴'},
  {'name': 'Oman', 'code': '+968', 'flag': '🇴🇲'},
  {'name': 'Pakistan', 'code': '+92', 'flag': '🇵🇰'},
  {'name': 'Palau', 'code': '+680', 'flag': '🇵🇼'},
  {'name': 'Palestine', 'code': '+970', 'flag': '🇵🇸'},
  {'name': 'Panama', 'code': '+507', 'flag': '🇵🇦'},
  {'name': 'Papua New Guinea', 'code': '+675', 'flag': '🇵🇬'},
  {'name': 'Paraguay', 'code': '+595', 'flag': '🇵🇾'},
  {'name': 'Peru', 'code': '+51', 'flag': '🇵🇪'},
  {'name': 'Philippines', 'code': '+63', 'flag': '🇵🇭'},
  {'name': 'Poland', 'code': '+48', 'flag': '🇵🇱'},
  {'name': 'Portugal', 'code': '+351', 'flag': '🇵🇹'},
  {'name': 'Qatar', 'code': '+974', 'flag': '🇶🇦'},
  {'name': 'Romania', 'code': '+40', 'flag': '🇷🇴'},
  {'name': 'Russia', 'code': '+7', 'flag': '🇷🇺'},
  {'name': 'Rwanda', 'code': '+250', 'flag': '🇷🇼'},
  {'name': 'Saint Kitts and Nevis', 'code': '+1-869', 'flag': '🇰🇳'},
  {'name': 'Saint Lucia', 'code': '+1-758', 'flag': '🇱🇨'},
  {'name': 'Saint Vincent and the Grenadines', 'code': '+1-784', 'flag': '🇻🇨'},
  {'name': 'Samoa', 'code': '+685', 'flag': '🇼🇸'},
  {'name': 'San Marino', 'code': '+378', 'flag': '🇸🇲'},
  {'name': 'Sao Tome and Principe', 'code': '+239', 'flag': '🇸🇹'},
  {'name': 'Saudi Arabia', 'code': '+966', 'flag': '🇸🇦'},
  {'name': 'Senegal', 'code': '+221', 'flag': '🇸🇳'},
  {'name': 'Serbia', 'code': '+381', 'flag': '🇷🇸'},
  {'name': 'Seychelles', 'code': '+248', 'flag': '🇸🇨'},
  {'name': 'Sierra Leone', 'code': '+232', 'flag': '🇸🇱'},
  {'name': 'Singapore', 'code': '+65', 'flag': '🇸🇬'},
  {'name': 'Slovakia', 'code': '+421', 'flag': '🇸🇰'},
  {'name': 'Slovenia', 'code': '+386', 'flag': '🇸🇮'},
  {'name': 'Solomon Islands', 'code': '+677', 'flag': '🇸🇧'},
  {'name': 'Somalia', 'code': '+252', 'flag': '🇸🇴'},
  {'name': 'South Africa', 'code': '+27', 'flag': '🇿🇦'},
  {'name': 'South Korea', 'code': '+82', 'flag': '🇰🇷'},
  {'name': 'South Sudan', 'code': '+211', 'flag': '🇸🇸'},
  {'name': 'Spain', 'code': '+34', 'flag': '🇪🇸'},
  {'name': 'Sri Lanka', 'code': '+94', 'flag': '🇱🇰'},
  {'name': 'Sudan', 'code': '+249', 'flag': '🇸🇩'},
  {'name': 'Suriname', 'code': '+597', 'flag': '🇸🇷'},
  {'name': 'Sweden', 'code': '+46', 'flag': '🇸🇪'},
  {'name': 'Switzerland', 'code': '+41', 'flag': '🇨🇭'},
  {'name': 'Syria', 'code': '+963', 'flag': '🇸🇾'},
  {'name': 'Taiwan', 'code': '+886', 'flag': '🇹🇼'},
  {'name': 'Tajikistan', 'code': '+992', 'flag': '🇹🇯'},
  {'name': 'Tanzania', 'code': '+255', 'flag': '🇹🇿'},
  {'name': 'Thailand', 'code': '+66', 'flag': '🇹🇭'},
  {'name': 'Togo', 'code': '+228', 'flag': '🇹🇬'},
  {'name': 'Tonga', 'code': '+676', 'flag': '🇹🇴'},
  {'name': 'Trinidad and Tobago', 'code': '+1-868', 'flag': '🇹🇹'},
  {'name': 'Tunisia', 'code': '+216', 'flag': '🇹🇳'},
  {'name': 'Turkey', 'code': '+90', 'flag': '🇹🇷'},
  {'name': 'Turkmenistan', 'code': '+993', 'flag': '🇹🇲'},
  {'name': 'Tuvalu', 'code': '+688', 'flag': '🇹🇻'},
  {'name': 'Uganda', 'code': '+256', 'flag': '🇺🇬'},
  {'name': 'Ukraine', 'code': '+380', 'flag': '🇺🇦'},
  {'name': 'United Arab Emirates', 'code': '+971', 'flag': '🇦🇪'},
  {'name': 'United Kingdom', 'code': '+44', 'flag': '🇬🇧'},
  {'name': 'United States', 'code': '+1', 'flag': '🇺🇸'},
  {'name': 'Uruguay', 'code': '+598', 'flag': '🇺🇾'},
  {'name': 'Uzbekistan', 'code': '+998', 'flag': '🇺🇿'},
  {'name': 'Vanuatu', 'code': '+678', 'flag': '🇻🇺'},
  {'name': 'Vatican City', 'code': '+39', 'flag': '🇻🇦'},
  {'name': 'Venezuela', 'code': '+58', 'flag': '🇻🇪'},
  {'name': 'Vietnam', 'code': '+84', 'flag': '🇻🇳'},
  {'name': 'Yemen', 'code': '+967', 'flag': '🇾🇪'},
  {'name': 'Zambia', 'code': '+260', 'flag': '🇿🇲'},
  {'name': 'Zimbabwe', 'code': '+263', 'flag': '🇿🇼'},
];

  bool _loading = true;
  bool _saving = false;
  User? _currentUser;
  bool _editingName = false;
  File? _profileImageFile;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final username = user.email?.split('@')[0];
    if (username == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(username).get();
    final data = userDoc.data() ?? {};
    setState(() {
      _nameController.text = data['name'] ?? user.displayName ?? 'User';
      _emailController.text = user.email ?? 'user@example.com';
      _phoneController.text = data['phone'] ?? '';
      _cityController.text = data['city'] ?? '';
      _ageGroup = data['ageGroup'] ?? null;
      _country = data['country'] ?? null;
      if (_country != null) {
        final found = _countries.firstWhere((c) => c['name'] == _country, orElse: () => _countries[0]);
        _countryCode = found['code'];
      }
      _profileImageUrl = data['profileImage'];
      _loading = false;
    });
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _profileImageFile = File(picked.path);
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final username = user.email?.split('@')[0];
    if (username == null) return;
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(username);
    Map<String, dynamic> updateData = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'city': _cityController.text.trim(),
      'ageGroup': _ageGroup,
      'country': _country,
    };
    if (_profileImageFile != null) {
      final storageRef = FirebaseStorage.instance.ref().child('profile_images/$username.jpg');
      await storageRef.putFile(_profileImageFile!);
      final url = await storageRef.getDownloadURL();
      updateData['profileImage'] = url;
      _profileImageUrl = url;
    }
    await userDocRef.set(updateData, SetOptions(merge: true));
    setState(() => _saving = false);
    showCustomSnackBar(context, 'Profile saved!', icon: Icons.check_circle_outline, backgroundColor: Color(0xFFEA8C6E));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Widget _buildProfileImage() {
    Widget imageWidget;
    if (_profileImageFile != null) {
      imageWidget = Image.file(_profileImageFile!, width: 60.0 * scale, height: 60.0 * scale, fit: BoxFit.cover);
    } else if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: _profileImageUrl!,
        width: 60.0 * scale,
        height: 60.0 * scale,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 60.0 * scale,
          height: 60.0 * scale,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person,
            size: 30.0 * scale,
            color: Colors.grey[600],
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: 60.0 * scale,
          height: 60.0 * scale,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person,
            size: 30.0 * scale,
            color: Colors.grey[600],
          ),
        ),
      );
    } else {
      imageWidget = Container(
        width: 60.0 * scale,
        height: 60.0 * scale,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.person, size: 30.0 * scale, color: Colors.grey[600]),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        imageWidget,
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 2)],
              ),
              child: Icon(Icons.edit, size: 18 * scale, color: Color(0xFFB98B6C)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Compact scaling factors
    // Colors
    const backgroundColor = Color(0xFFFDD5D1);
    const cardColor = Color(0xFFFFF7E9);
    const headerGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.fromARGB(255, 218, 177, 161), Color(0x00E7BBAA)],
      stops: [0.0, 1.0],
    );
    const labelColor = Color(0xFF8B7B9B);
    const borderColor = Color(0xFFE7BBAA);
    const fieldTextColor = Color(0xFF222222);
    const iconColor = Color(0xFFB98B6C);
    const saveTextColor = Color(0xFF222222);
    const nameTextColor = Color(0xFF222222);
    const editIconColor = Color(0xFFB98B6C);
    const fieldFont = 'Montserrat';
    const nameFont = 'Montserrat';
    const countryIcon = Icons.flag_outlined;
    const ageIcon = Icons.badge_outlined;
    const phoneIcon = Icons.phone_outlined;
    // Sizing (scaled down, but with +2px for readability)
    const double cardRadius = 36 * scale;
    const double cardPadding = 32 * scale;
    const double avatarRadius = 60 * scale;
    const double avatarCircleRadius = 80 * scale;
    const double editIconSize = 22 * scale;
    const double nameFontSize = 24 * scale + 8;
    const double fieldFontSize = 16 * scale + 6;
    const double labelFontSize = 10 * scale + 6;
    const double fieldVerticalSpacing = 8 * scale;
    const double saveFontSize = 18 * scale + 6;
    const double headerHeight = 76 * scale;
    const double headerRadius = 36 * scale;
    const double backIconSize = 32 * scale;
    const double topSafeArea = 28 * scale;
    const double cardMargin = 12 * scale;
    const double containerWidth = 320;
    const double containerHeight = 600;

    if (_loading) {
      return const Scaffold(
        backgroundColor: backgroundColor,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Container(
          width: containerWidth,
          height: containerHeight,
          margin: EdgeInsets.symmetric(
            vertical: cardMargin,
            horizontal: cardMargin,
          ),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(cardRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 12 * scale,
                offset: Offset(0, 6 * scale),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Header with gradient and Save button
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  height: headerHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(headerRadius),
                      topRight: Radius.circular(headerRadius),
                    ),
                    gradient: headerGradient,
                  ),
                  child: Stack(
                    children: [
                      // Back arrow
                      Positioned(
                        left: 12 * scale,
                        top: topSafeArea,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: backIconSize,
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      // Title
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment(0, -0.1),
                          child: Text(
                            'Edit profile',
                            style: TextStyle(
                              fontFamily: nameFont,
                              fontWeight: FontWeight.w600,
                              fontSize: 21 * scale + 4,
                              color: nameTextColor,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                      // Save button
                      Positioned(
                        right: 18 * scale,
                        top: topSafeArea,
                        child: GestureDetector(
                          onTap: _saving ? null : _saveProfile,
                          child: _saving
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      saveTextColor.withOpacity(0.7),
                                    ),
                                  ),
                                )
                              : Text(
                                  'Save',
                                  style: TextStyle(
                                    fontFamily: nameFont,
                                    fontWeight: FontWeight.w400,
                                    fontSize: saveFontSize,
                                    color: saveTextColor,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Main content
              Positioned.fill(
                top: headerHeight - 8 * scale,
                child: Column(
                  children: [
                    SizedBox(height: 12 * scale),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Avatar circle
                        Container(
                          width: avatarCircleRadius,
                          height: avatarCircleRadius,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                        ),
                        // Profile image
                        ClipOval(child: _buildProfileImage()),
                      ],
                    ),
                    SizedBox(height: 4 * scale),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        !_editingName
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _nameController.text,
                                    style: TextStyle(
                                      fontFamily: nameFont,
                                      fontWeight: FontWeight.w500,
                                      fontSize: nameFontSize - 2,
                                      color: nameTextColor,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _editingName = true;
                                      });
                                    },
                                    child: Icon(
                                      Icons.edit,
                                      size: editIconSize,
                                      color: editIconColor,
                                    ),
                                  ),
                                ],
                              )
                            : SizedBox(
                                width: 180,
                                child: TextField(
                                  controller: _nameController,
                                  autofocus: true,
                                  style: TextStyle(
                                    fontFamily: nameFont,
                                    fontWeight: FontWeight.w500,
                                    fontSize: nameFontSize - 2,
                                    color: nameTextColor,
                                    letterSpacing: 0.1,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 0,
                                    ),
                                  ),
                                  textAlign: TextAlign.center,
                                  onSubmitted: (_) {
                                    setState(() {
                                      _editingName = false;
                                    });
                                  },
                                  onEditingComplete: () {
                                    setState(() {
                                      _editingName = false;
                                    });
                                  },
                                ),
                              ),
                      ],
                    ),
                    SizedBox(height: 4 * scale),
                    // Fields
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          cardPadding,
                          0,
                          cardPadding,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Email
                            _Label('EMAIL', fontSize: labelFontSize),
                            TextField(
                              controller: _emailController,
                              readOnly: true,
                              style: TextStyle(
                                fontFamily: fieldFont,
                                fontWeight: FontWeight.w400,
                              fontSize: fieldFontSize,
                                color: fieldTextColor.withOpacity(0.7),
                                letterSpacing: 0.1,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 0,
                                  horizontal: 0,
                                ),
                              ),
                            ),
                            SizedBox(height: fieldVerticalSpacing),
                            // Age Group
                            _Label('AGE GROUP', fontSize: labelFontSize),
                            DropdownButtonFormField<String>(
                              value: _ageGroup,
                              items: _ageGroups
                                  .map((e) => DropdownMenuItem(
                                        value: e['value'],
                                        child: Row(
                                          children: [
                                            Text(e['label']!, style: TextStyle(fontFamily: fieldFont, fontSize: fieldFontSize, color: fieldTextColor)),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (val) => setState(() => _ageGroup = val),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 0,
                                  horizontal: 0,
                                ),
                              ),
                              style: TextStyle(fontFamily: fieldFont, fontSize: fieldFontSize, color: fieldTextColor),
                              dropdownColor: const Color(0xFFFCF6ED),
                            ),
                            SizedBox(height: fieldVerticalSpacing),
                            // Phone
                            _Label('PHONE', fontSize: labelFontSize),
                            _IconEditableField(
                              icon: phoneIcon,
                              controller: _phoneController,
                              fontSize: fieldFontSize,
                              textColor: fieldTextColor,
                              borderColor: borderColor,
                              fontFamily: fieldFont,
                              keyboardType: TextInputType.phone,
                            ),
                            SizedBox(height: fieldVerticalSpacing),
                            // City
                            _Label('CITY', fontSize: labelFontSize),
                            _EditableField(
                              controller: _cityController,
                              fontSize: fieldFontSize,
                              underline: true,
                              textColor: fieldTextColor,
                              borderColor: borderColor,
                              fontFamily: fieldFont,
                            ),
                            SizedBox(height: fieldVerticalSpacing),
                            // Country
                            _Label('COUNTRY', fontSize: labelFontSize),
                            GestureDetector(
                              onTap: () async {
                                String search = '';
                                List<Map<String, String>> filtered = List.from(_countries);
                                final selected = await showDialog<String>(
                                  context: context,
                                  builder: (context) {
                                    return StatefulBuilder(
                                      builder: (context, setState) => AlertDialog(
                                        title: const Text('Select Country'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextField(
                                              decoration: const InputDecoration(
                                                hintText: 'Search country',
                                              ),
                                              onChanged: (val) {
                                                setState(() {
                                                  search = val;
                                                  filtered = _countries
                                                      .where((c) => c['name']!.toLowerCase().contains(search.toLowerCase()))
                                                      .toList();
                                                });
                                              },
                                            ),
                                            const SizedBox(height: 8),
                                            SizedBox(
                                              height: 250,
                                              width: 300,
                                              child: ListView.builder(
                                                itemCount: filtered.length,
                                                itemBuilder: (context, i) {
                                                  final c = filtered[i];
                                                  return ListTile(
                                                    leading: Text(c['flag'] ?? '', style: const TextStyle(fontSize: 20)),
                                                    title: Text(c['name'] ?? ''),
                                                    onTap: () => Navigator.pop(context, c['name']),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                                if (selected != null) {
                                  setState(() {
                                    _country = selected;
                                    _countryCode = _countries.firstWhere((c) => c['name'] == selected)['code'];
                                  });
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: Color(0xFFE7BBAA)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(_countries.firstWhere((c) => c['name'] == _country, orElse: () => {'flag': ''})['flag'] ?? '', style: const TextStyle(fontSize: 16)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _country ?? 'Select Country',
                                        style: TextStyle(fontSize: fieldFontSize, fontFamily: fieldFont, color: fieldTextColor),
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down, color: Color(0xFFB98B6C)),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: fieldVerticalSpacing),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final double fontSize;
  const _Label(this.text, {super.key, this.fontSize = 15.5});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.5),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w500,
          fontSize: fontSize,
          color: Color(0xFF8B7B9B),
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _EditableField extends StatelessWidget {
  final TextEditingController controller;
  final double fontSize;
  final bool underline;
  final Color textColor;
  final Color borderColor;
  final String fontFamily;
  final TextInputType? keyboardType;
  const _EditableField({
    required this.controller,
    required this.fontSize,
    required this.underline,
    required this.textColor,
    required this.borderColor,
    required this.fontFamily,
    this.keyboardType,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontWeight: FontWeight.w400,
                    fontSize: fontSize,
                    color: textColor,
                    letterSpacing: 0.1,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 0,
                    ),
                  ),
                  keyboardType: keyboardType,
                ),
              ),
            ],
          ),
          if (underline)
            Container(
              margin: EdgeInsets.only(top: 2),
              width: double.infinity,
              height: 1.2,
              color: borderColor,
          ),
        ],
      ),
    );
  }
}

class _IconEditableField extends StatelessWidget {
  final IconData icon;
  final TextEditingController controller;
  final double fontSize;
  final Color textColor;
  final Color borderColor;
  final String fontFamily;
  final TextInputType? keyboardType;
  const _IconEditableField({
    required this.icon,
    required this.controller,
    required this.fontSize,
    required this.textColor,
    required this.borderColor,
    required this.fontFamily,
    this.keyboardType,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Color(0xFFB98B6C)),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontFamily: fontFamily,
                fontWeight: FontWeight.w400,
                fontSize: fontSize,
                color: textColor,
                letterSpacing: 0.1,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 0,
                ),
              ),
              keyboardType: keyboardType,
            ),
          ),
        ],
      ),
    );
  }
}
