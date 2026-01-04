import 'package:flutter/material.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({Key? key}) : super(key: key);

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final List<_FaqItem> _faqs = [
    _FaqItem('What is MindMate?', 'MindMate is your personal mental wellness companion, designed to help you manage your thoughts, feelings, and daily reflections.'),
    _FaqItem('Is MindMate free to use?', 'Yes, MindMate is completely free to use.'),
    _FaqItem('Can I customize my experience?', 'Absolutely! MindMate allows you to personalize your experience to suit your needs.'),
    _FaqItem('Is my data safe?', 'Your data is private and securely stored. Only you have access to your information.'),
    _FaqItem('Who can use this app?', 'Anyone looking to improve their mental wellness can use MindMate.'),
    _FaqItem('Do I need an internet connection?', 'An internet connection is required for syncing and backup, but some features may work offline.'),
    _FaqItem('How often should I use MindMate?', 'You can use MindMate as often as you like. Daily use is recommended for best results.'),
  ];
  List<bool> _expanded = List.generate(7, (index) => false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFD9D0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 32.0),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E9),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              children: [
                // Header with gradient and rounded top corners
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFDD5D1), Color(0xFFE7BBAA)],
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 16, left: 8, right: 8, bottom: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Help',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 48), // To balance the back button
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    itemCount: _faqs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      return Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Color(0xFFFFDDD1), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ExpansionPanelList(
                            elevation: 0,
                            expandedHeaderPadding: EdgeInsets.zero,
                            expansionCallback: (panelIndex, isExpanded) {
                              setState(() {
                                _expanded[index] = !_expanded[index];
                              });
                            },
                            animationDuration: const Duration(milliseconds: 250),
                            children: [
                              ExpansionPanel(
                                canTapOnHeader: true,
                                isExpanded: _expanded[index],
                                headerBuilder: (context, isExpanded) {
                                  return ListTile(
                                    title: Text(
                                      _faqs[index].question,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                  );
                                },
                                body: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Text(
                                    _faqs[index].answer,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;
  _FaqItem(this.question, this.answer);
}
