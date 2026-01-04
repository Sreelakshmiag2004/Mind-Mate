import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'regfav.dart';

// Data model for a person in the favourites list
class SupportPerson {
  final String relationship;
  final String sinceDate;
  final bool showStressButton;

  SupportPerson({
    required this.relationship,
    required this.sinceDate,
    this.showStressButton = false,
  });
}

// The main screen widget
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  // 0 for "My supporters", 1 for "I'm supporting"
  int _selectedTabIndex = 1;

  List<SupportPerson> _supportingList = [];
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingInvites = [];
  bool _loadingInvites = false;

  @override
  void initState() {
    super.initState();
    _fetchComfortPerson();
  }

  Future<void> _fetchComfortPerson() async {
    setState(() { _isLoading = true; });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() { _isLoading = false; });
      return;
    }
    final username = user.email!.split('@')[0];
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(username).get();
    if (userDoc.exists && userDoc.data() != null) {
      final data = userDoc.data()!;
      final comfortPerson = data['comfortPerson'];
      if (comfortPerson != null && comfortPerson['relation'] != null) {
        final person = SupportPerson(
          relationship: comfortPerson['customRelation'] ?? comfortPerson['relation'],
          sinceDate: 'Added on ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
          showStressButton: true,
        );
        setState(() { _supportingList = [person]; });
      }
    }
    setState(() { _isLoading = false; });
  }

  Future<void> _showPendingInvitesDialog() async {
    setState(() { _loadingInvites = true; });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    List<dynamic> pending = doc.data()?['pendingInvitesReceived'] ?? [];
    List<Map<String, dynamic>> invites = [];
    for (String uid in pending) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        invites.add({
          'uid': uid,
          'name': userDoc.data()!['name'] ?? '',
          'email': userDoc.data()!['email'] ?? '',
        });
      }
    }
    setState(() {
      _pendingInvites = invites;
      _loadingInvites = false;
    });
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pending Invites'),
        content: _loadingInvites
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : _pendingInvites.isEmpty
                ? const Text('No pending invites.')
                : SizedBox(
                    width: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _pendingInvites.length,
                      itemBuilder: (context, index) {
                        final invite = _pendingInvites[index];
                        return ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(invite['name'] ?? ''),
                          subtitle: Text(invite['email'] ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                tooltip: 'Accept',
                                onPressed: () async {
                                  await _acceptInvite(invite['uid']);
                                  Navigator.of(context).pop();
                                  _showPendingInvitesDialog();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                tooltip: 'Decline',
                                onPressed: () async {
                                  await _declineInvite(invite['uid']);
                                  Navigator.of(context).pop();
                                  _showPendingInvitesDialog();
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  Future<void> _acceptInvite(String senderUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // For now, just remove from pendingInvitesReceived and pendingInvitesSent
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'pendingInvitesReceived': FieldValue.arrayRemove([senderUid]),
      'myComfortCircle': FieldValue.arrayUnion([senderUid]),
    });
    await FirebaseFirestore.instance.collection('users').doc(senderUid).update({
      'pendingInvitesSent': FieldValue.arrayRemove([user.uid]),
      'inTheirCircle': FieldValue.arrayUnion([user.uid]),
    });
    setState(() { _pendingInvites.removeWhere((i) => i['uid'] == senderUid); });
  }

  Future<void> _declineInvite(String senderUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'pendingInvitesReceived': FieldValue.arrayRemove([senderUid]),
    });
    await FirebaseFirestore.instance.collection('users').doc(senderUid).update({
      'pendingInvitesSent': FieldValue.arrayRemove([user.uid]),
    });
    setState(() { _pendingInvites.removeWhere((i) => i['uid'] == senderUid); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favourites'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Add Comfort Person',
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const RegFavPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Pending Invites',
            onPressed: _showPendingInvitesDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Removed decorative leaf asset
          // Main content
          Column(
            children: [
              _buildCustomTabBar(),
              _buildContent(),
            ],
          ),
        ],
      ),
    );
  }
  
  // Widget for the custom tab bar
  Widget _buildCustomTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Container(
        padding: const EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Row(
          children: [
            Expanded(child: _buildTabButton("My supporters", 0)),
            Expanded(child: _buildTabButton("I'm supporting", 1)),
          ],
        ),
      ),
    );
  }

  // Helper widget to build each tab button
  Widget _buildTabButton(String text, int index) {
    bool isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF9C5D1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // Widget to display content based on the selected tab
  Widget _buildContent() {
    if (_isLoading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }
    final List<SupportPerson> currentList = _selectedTabIndex == 0 ? [] : _supportingList;
    if (currentList.isEmpty) {
      return const Expanded(
        child: Center(
          child: Text(
            'No one here yet!',
            style: TextStyle(color: Colors.grey, fontSize: 16)
          ),
        ),
      );
    }
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        itemCount: currentList.length,
        itemBuilder: (context, index) {
          return SupportCard(person: currentList[index]);
        },
      ),
    );
  }
}


// Widget for the individual card in the list
class SupportCard extends StatelessWidget {
  final SupportPerson person;

  const SupportCard({super.key, required this.person});

  // Helper to build styled text with a bolded value
  Widget _buildRichText(String label, String value) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(color: Colors.black54, fontSize: 15),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEA), // Light cream color for the card
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Relationship text
              _buildRichText('Relationship', person.relationship),
              // Delete icon
              InkWell(
                onTap: () {
                  // TODO: Implement delete functionality
                },
                child: const Icon(Icons.delete, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Supporting since text
          _buildRichText('Supporting since', person.sinceDate),
          
          // Conditionally show the stress level button
          if (person.showStressButton) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () {
                  // TODO: Implement stress level view
                },
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFDE4E4),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "View today's stress level",
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}