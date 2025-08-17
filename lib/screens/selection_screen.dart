// lib/screens/selection_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:course_application/screens/notes_display_screen.dart';
import 'package:course_application/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';

// ===== MODELS =====
class ClassModel {
  final String id;
  final String name;
  ClassModel({required this.id, required this.name});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ClassModel && runtimeType == other.runtimeType && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

class PatternModel {
  final String id;
  final String name;
  PatternModel({required this.id, required this.name});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is PatternModel && runtimeType == other.runtimeType && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

class SubjectModel {
  final String id;
  final String name;
  SubjectModel({required this.id, required this.name});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SubjectModel && runtimeType == other.runtimeType && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

class ChapterModel {
  final String id;
  final String name;
  ChapterModel({required this.id, required this.name});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ChapterModel && runtimeType == other.runtimeType && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

// ===== MAIN WIDGET =====
class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});
  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  // --- State Variables ---
  List<ClassModel> _classes = [];
  List<PatternModel> _patterns = [];
  List<SubjectModel> _subjects = [];
  List<ChapterModel> _chapters = [];
  ClassModel? _selectedClass;
  PatternModel? _selectedPattern;
  SubjectModel? _selectedSubject;
  ChapterModel? _selectedChapter;
  bool _isLoadingClasses = true;
  bool _isLoadingPatterns = false;
  bool _isLoadingSubjects = false;
  bool _isLoadingChapters = false;
  bool _isFetchingNotes = false;

  final DatabaseService _databaseService = DatabaseService();
  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _fetchClasses();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  // --- Payment Handlers ---
  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    print("✅ Payment Successful! Verifying on server...");
    _verifyPayment(
      orderId: response.orderId!,
      paymentId: response.paymentId!,
      signature: response.signature!,
      classId: _selectedClass!.id,
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    print("❌ Payment Failed: ${response.message}");
    if (mounted) {
      setState(() => _isFetchingNotes = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Payment failed: ${response.message}"), backgroundColor: Colors.red),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print("External Wallet Used: ${response.walletName}");
  }

  // --- Data Fetching Functions ---
  Future<void> _fetchClasses() async {
    setState(() => _isLoadingClasses = true);
    final snapshot = await FirebaseFirestore.instance.collection('classes').get();
    _classes = snapshot.docs.map((doc) => ClassModel(id: doc.id, name: doc.data()['name'])).toList();
    setState(() => _isLoadingClasses = false);
  }

  Future<void> _fetchPatterns(String classId) async {
    setState(() {
      _isLoadingPatterns = true;
      _patterns = []; _subjects = []; _chapters = [];
      _selectedPattern = null; _selectedSubject = null; _selectedChapter = null;
    });
    final snapshot = await FirebaseFirestore.instance.collection('classes').doc(classId).collection('patterns').get();
    _patterns = snapshot.docs.map((doc) => PatternModel(id: doc.id, name: doc.data()['name'])).toList();
    setState(() => _isLoadingPatterns = false);
  }

  Future<void> _fetchSubjects(String classId, String patternId) async {
    setState(() {
      _isLoadingSubjects = true;
      _subjects = []; _chapters = [];
      _selectedSubject = null; _selectedChapter = null;
    });
    final snapshot = await FirebaseFirestore.instance.collection('classes').doc(classId).collection('patterns').doc(patternId).collection('subjects').get();
    _subjects = snapshot.docs.map((doc) => SubjectModel(id: doc.id, name: doc.data()['name'])).toList();
    setState(() => _isLoadingSubjects = false);
  }

  Future<void> _fetchChapters(String classId, String patternId, String subjectId) async {
    setState(() {
      _isLoadingChapters = true;
      _chapters = [];
      _selectedChapter = null;
    });
    final snapshot = await FirebaseFirestore.instance.collection('classes').doc(classId).collection('patterns').doc(patternId).collection('subjects').doc(subjectId).collection('chapters').get();
    _chapters = snapshot.docs.map((doc) => ChapterModel(id: doc.id, name: doc.data()['name'])).toList();
    setState(() => _isLoadingChapters = false);
  }


  // --- Core Logic for Notes & Payment ---
  void _onGetNotesPressed() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please log in first!")));
      return;
    }
    if (_selectedClass == null) return;

    setState(() => _isFetchingNotes = true);

    final dbService = DatabaseService(uid: currentUser.uid);
    final hasAccess = await dbService.hasAccessToClass(_selectedClass!.id);

    if (hasAccess) {
      print("User already has access. Fetching notes...");
      _fetchNotesForDisplay();
    } else {
      print("User does not have access. Showing payment popup.");
      _showPaymentPopup();
    }
  }

  void _showPaymentPopup() {
    setState(() => _isFetchingNotes = false);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text("Unlock Access", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text("To view all notes for '${_selectedClass!.name}', you need to make a one-time payment of ₹50."),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("Pay ₹50 Now", style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.of(context).pop();
                _startPayment();
              },
            ),
          ],
        );
      },
    );
  }

  void _startPayment() async {
    setState(() => _isFetchingNotes = true);
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('createRazorpayOrder');
      final result = await callable.call<Map<String, dynamic>>({
        'amount': 50, // Amount in Rupees
      });
      final String orderId = result.data['orderId'];

      var options = {
        'key': 'rzp_test_R63e5HcDWJPQmZ', // Your Razorpay Key ID
        'amount': 5000, // Amount in Paise (50 * 100)
        'name': 'Course Application',
        'order_id': orderId,
        'description': 'Access for ${_selectedClass!.name}',
        'prefill': {'email': FirebaseAuth.instance.currentUser?.email ?? ''}
      };
      _razorpay.open(options);
    } catch (e) {
      print("Error starting payment: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not start payment. Please try again.")));
      if (mounted) setState(() => _isFetchingNotes = false);
    }
  }

  Future<void> _verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
    required String classId,
  }) async {
    setState(() => _isFetchingNotes = true);
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('verifyRazorpayPayment');
      await callable.call(<String, dynamic>{
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
        'classId': classId,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Payment Verified! Access Granted."), backgroundColor: Colors.green),
      );
      _fetchNotesForDisplay();
    } on FirebaseFunctionsException catch (e) {
      print("Error verifying payment: ${e.code} - ${e.message}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Verification Failed: ${e.message}"), backgroundColor: Colors.red),
      );
      if (mounted) setState(() => _isFetchingNotes = false);
    }
  }

  void _fetchNotesForDisplay() async {
    final notes = await _databaseService.getNotes(
      classId: _selectedClass!.id,
      subjectId: _selectedSubject!.id,
      patternId: _selectedPattern!.id,
      chapterId: _selectedChapter!.id,
    );
    if (mounted) {
      setState(() => _isFetchingNotes = false);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => NotesDisplayScreen(notes: notes)),
      );
    }
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    bool allOptionsSelected = _selectedClass != null &&
        _selectedPattern != null &&
        _selectedSubject != null &&
        _selectedChapter != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('📚 Select Your Notes', style: GoogleFonts.poppins()),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDropdown<ClassModel>(
              label: 'Select Class',
              value: _selectedClass,
              items: _classes,
              onChanged: (value) {
                setState(() => _selectedClass = value);
                if (value != null) _fetchPatterns(value.id);
              },
              isLoading: _isLoadingClasses,
              itemAsString: (ClassModel c) => c.name,
            ),
            const SizedBox(height: 20.0),
            _buildDropdown<PatternModel>(
              label: 'Select Pattern',
              value: _selectedPattern,
              items: _patterns,
              onChanged: (value) {
                setState(() => _selectedPattern = value);
                if (_selectedClass != null && value != null) _fetchSubjects(_selectedClass!.id, value.id);
              },
              isLoading: _isLoadingPatterns,
              itemAsString: (PatternModel p) => p.name,
              isEnabled: _selectedClass != null,
            ),
            const SizedBox(height: 20.0),
            _buildDropdown<SubjectModel>(
              label: 'Select Subject',
              value: _selectedSubject,
              items: _subjects,
              onChanged: (value) {
                setState(() => _selectedSubject = value);
                if (_selectedClass != null && _selectedPattern != null && value != null) {
                  _fetchChapters(_selectedClass!.id, _selectedPattern!.id, value.id);
                }
              },
              isLoading: _isLoadingSubjects,
              itemAsString: (SubjectModel s) => s.name,
              isEnabled: _selectedPattern != null,
            ),
            const SizedBox(height: 20.0),
            _buildDropdown<ChapterModel>(
              label: 'Select Chapter',
              value: _selectedChapter,
              items: _chapters,
              onChanged: (value) {
                setState(() => _selectedChapter = value);
              },
              isLoading: _isLoadingChapters,
              itemAsString: (ChapterModel c) => c.name,
              isEnabled: _selectedSubject != null,
            ),
            const SizedBox(height: 40.0),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: allOptionsSelected ? Colors.green : Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
              ),
              onPressed: allOptionsSelected ? _onGetNotesPressed : null,
              child: _isFetchingNotes
                  ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                  : Text('Get Notes', style: GoogleFonts.poppins(fontSize: 18, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Widget for Dropdowns ---
  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required void Function(T?) onChanged,
    required String Function(T) itemAsString,
    bool isLoading = false,
    bool isEnabled = true,
  }) {
    return DropdownButtonFormField<T>(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
        filled: !isEnabled,
        fillColor: Colors.grey[200],
        prefixIcon: isLoading
            ? Transform.scale(scale: 0.5, child: const CircularProgressIndicator())
            : null,
      ),
      value: value,
      isExpanded: true,
      items: items.map((T item) {
        return DropdownMenuItem<T>(
          value: item,
          child: Text(itemAsString(item), style: GoogleFonts.poppins()),
        );
      }).toList(),
      onChanged: isEnabled ? onChanged : null,
      validator: (value) => value == null ? 'Please select an option' : null,
    );
  }
}