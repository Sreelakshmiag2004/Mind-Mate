import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class EnterDetailsPage extends StatefulWidget {
  @override
  _EnterDetailsPageState createState() => _EnterDetailsPageState();
}

class _EnterDetailsPageState extends State<EnterDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  String? _ageGroup, _country, _countryCode = '+91';
  File? _profileImage;
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _nameController = TextEditingController();

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

  final List<Map<String, String>> _ageGroups = [
    {'label': '🧒 Teenagers(13-17)', 'value': 'Teenagers(13-17)'},
    {'label': '🧑 Young adults(18-24)', 'value': 'Young adults(18-24)'},
    {'label': '🧔 Adults(25-34)', 'value': 'Adults(25-34)'},
    {'label': '👨‍🦳 Mid-aged(35-54)', 'value': 'Mid-aged(35-54)'},
    {'label': '👴 Seniors(55 & above)', 'value': 'Seniors(55 & above)'},
  ];

  @override
  void initState() {
    super.initState();
    _country = _countries.firstWhere((c) => c['code'] == _countryCode)['name'];
    _checkUserDetails();
  }

  Future<void> _checkUserDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final username = user.email?.split('@')[0];
    if (username == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(username).get();
    if (userDoc.exists && userDoc.data() != null && userDoc.data()!['name'] != null && userDoc.data()!['ageGroup'] != null && userDoc.data()!['phone'] != null && userDoc.data()!['city'] != null && userDoc.data()!['country'] != null) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/selectFavPerson');
      }
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _profileImage = File(picked.path);
      });
    }
  }

  Future<void> _saveDetails() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final email = user.email ?? '';
      final username = email.split('@')[0];
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(username);
      final userDoc = await userDocRef.get();
      final existing = userDoc.data() ?? {};
      Map<String, dynamic> updateData = {};
      if (existing['email'] == null) updateData['email'] = user.email;
      if (existing['name'] == null) updateData['name'] = _nameController.text.trim();
      if (existing['ageGroup'] == null) updateData['ageGroup'] = _ageGroup;
      if (existing['phone'] == null) updateData['phone'] = '$_countryCode ${_phoneController.text.trim()}';
      if (existing['city'] == null) updateData['city'] = _cityController.text.trim();
      if (existing['country'] == null) updateData['country'] = _country;
      String profileImageUrl = '';
      if (_profileImage != null) {
        final storageRef = FirebaseStorage.instance.ref().child('profile_images/$username.jpg');
        await storageRef.putFile(_profileImage!);
        profileImageUrl = await storageRef.getDownloadURL();
      } else {
        profileImageUrl = 'https://firebasestorage.googleapis.com/v0/b/mindmate-2025.firebasestorage.app/o/logo.png?alt=media&token=25c8c1a6-d30a-40c5-b84d-75327cd45ee5';
      }
      updateData['profileImage'] = profileImageUrl;
      if (updateData.isNotEmpty) {
        await userDocRef.update(updateData);
      }
      Navigator.pushReplacementNamed(context, '/selectFavPerson');
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _cityController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // Add this helper to get the selected country's data
  Map<String, String> get _selectedCountryData =>
      _countries.firstWhere((c) => c['name'] == _country, orElse: () => {'flag': '', 'code': ''});

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFFDE7EF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF6ED),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Gradient Top Bar
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFD08270), Color(0xFFFDDDD0)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(28),
                          topRight: Radius.circular(28),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(
                            child: Center(
                              child: Text(
                                'Enter Your Details',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Montserrat',
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _saveDetails,
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 12),
                            // Profile picture
                            Center(
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 66,
                                    backgroundColor: const Color(0xFFE7BFA7),
                                    backgroundImage: _profileImage != null
                                        ? FileImage(_profileImage!)
                                        : const AssetImage('assets/logo.png') as ImageProvider,
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: IconButton(
                                      icon: const Icon(Icons.edit, color: Color(0xFFDA8D7A), size: 20),
                                      onPressed: _pickImage,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Name
                            TextFormField(
                              controller: _nameController,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                hintText: 'your name',
                                border: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 0),
                              ),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Montserrat',
                                color: Colors.black,
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 20),
                            // Email (read-only)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'EMAIL',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                            ),
                            TextFormField(
                              initialValue: email,
                              readOnly: true,
                              decoration: const InputDecoration(
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8C8B2), width: 2),
                                ),
                                prefix: Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.email, color: Color(0xFFDA8D7A), size: 20),
                                ),
                                contentPadding: EdgeInsets.only(left: 0, top: 14, bottom: 14),
                              ),
                              style: const TextStyle(fontSize: 15, fontFamily: 'Montserrat'),
                              textAlignVertical: TextAlignVertical.center,
                            ),
                            const SizedBox(height: 12),
                            // Age Group
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'AGE GROUP',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              value: _ageGroup,
                              items: _ageGroups
                                  .map((e) => DropdownMenuItem(
                                        value: e['value'],
                                        child: Row(
                                          children: [
                                            Text(e['label']!, style: const TextStyle(fontFamily: 'Montserrat', fontSize: 14, color: Colors.black)),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (val) => setState(() => _ageGroup = val),
                              validator: (val) => val == null ? 'Required' : null,
                              decoration: const InputDecoration(
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8C8B2), width: 2),
                                ),
                              ),
                              hint: Row(
                                children: [
                                  Icon(Icons.badge_outlined, color: Color(0xFFDA8D7A), size: 20),
                                  SizedBox(width: 8),
                                  Text('Select Age Group', style: TextStyle(fontFamily: 'Montserrat', fontSize: 14, color: Colors.black)),
                                ],
                              ),
                              style: const TextStyle(fontSize: 14, fontFamily: 'Montserrat', color: Colors.black),
                              dropdownColor: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            // Phone
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'PHONE',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 48,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Flag (based on selected country)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Text(
                                      _selectedCountryData['flag'] ?? '',
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                  ),
                                  // Country code text field (auto-updates with country selection)
                                  SizedBox(
                                    width: 70,
                                    child: TextFormField(
                                      controller: TextEditingController(text: _selectedCountryData['code'] ?? _countryCode),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                                        border: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                        ),
                                        enabledBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                        ),
                                        focusedBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Color(0xFFF8C8B2), width: 2),
                                        ),
                                        hintText: '+91',
                                      ),
                                      keyboardType: TextInputType.phone,
                                      validator: (val) {
                                        if (val == null || val.isEmpty) return 'Required';
                                        if (!RegExp(r'^\+[0-9\-]{1,7} $').hasMatch(val + '\u0000')) return 'Invalid';
                                        return null;
                                      },
                                      onChanged: (val) {
                                        setState(() {
                                          _countryCode = val;
                                        });
                                      },
                                      style: const TextStyle(fontSize: 14, fontFamily: 'Montserrat', color: Colors.black),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _phoneController,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                                        border: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                        ),
                                        enabledBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                        ),
                                        focusedBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Color(0xFFF8C8B2), width: 2),
                                        ),
                                      ),
                                      validator: (val) {
                                        if (val == null || val.isEmpty) return 'Required';
                                        if (!RegExp(r'^[0-9]{7,15}$').hasMatch(val)) return 'Invalid phone number';
                                        return null;
                                      },
                                      style: const TextStyle(fontSize: 14, fontFamily: 'Montserrat', color: Colors.black),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // City
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'CITY',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                            ),
                            TextFormField(
                              controller: _cityController,
                              textAlignVertical: TextAlignVertical.center,
                              decoration: const InputDecoration(
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8C8B2)),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8C8B2), width: 2),
                                ),
                                prefix: Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.location_city, color: Color(0xFFDA8D7A), size: 20),
                                ),
                                contentPadding: EdgeInsets.only(left: 0, top: 14, bottom: 14),
                              ),
                              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                              style: const TextStyle(fontSize: 14, fontFamily: 'Montserrat', color: Colors.black),
                            ),
                            const SizedBox(height: 12),
                            // Country
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'COUNTRY',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final selected = await showDialog<String>(
                                  context: context,
                                  builder: (context) {
                                    String search = '';
                                    List<Map<String, String>> filtered = List.from(_countries);
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
                                    _countryCode = _countries.firstWhere((c) => c['name'] == selected)['code']!;
                                  });
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: Color(0xFFF8C8B2)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(_selectedCountryData['flag'] ?? '', style: const TextStyle(fontSize: 16)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _country ?? 'Select Country',
                                        style: const TextStyle(fontSize: 14, fontFamily: 'Montserrat', color: Colors.black),
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down, color: Color(0xFFDA8D7A)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
