import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'notes_display_screen.dart';

class Class {
  final String id;
  final String name;
  final String description;

  Class({required this.id, required this.name, required this.description});

  factory Class.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Class(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
    );
  }
}

class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  List<Class> _classes = [];
  Class? _selectedClass;
  bool _isLoading = true;
  bool _isFetchingNotes = false;
  bool _hasPurchased = false;

  late Razorpay _razorpay;
  String _razorpayKey = '';

  @override
  void initState() {
    super.initState();
    _fetchClasses();
    _setupRemoteConfig();
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

  Future<void> _setupRemoteConfig() async {
    try {
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await _remoteConfig.fetchAndActivate();
      // Remote config se key fetch karein
      final key = _remoteConfig.getString('razorpay_key_id');
      if (key.isNotEmpty) {
        setState(() {
          _razorpayKey = key;
        });
        print("Razorpay Key Loaded from Remote Config!");
      } else {
        print("Razorpay Key Remote Config mein nahi mili!");
      }
    } catch (e) {
      print("Remote Config fetch nahi kar paya: $e");
    }
  }


  Future<void> _fetchClasses() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('classes').get();
      final classes = snapshot.docs.map((doc) => Class.fromFirestore(doc)).toList();
      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching classes: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkIfPurchased() async {
    if (_selectedClass == null) return;
    setState(() => _isFetchingNotes = true);
    try {
      final userDoc = await _firestore.collection('users').doc(_auth.currentUser!.uid).get();
      if (userDoc.exists && userDoc.data()!.containsKey('purchasedClasses')) {
        final List purchasedClasses = userDoc.data()!['purchasedClasses'];
        setState(() {
          _hasPurchased = purchasedClasses.contains(_selectedClass!.id);
        });
      } else {
        setState(() {
          _hasPurchased = false;
        });
      }
    } catch (e) {
      print("Error checking purchase status: $e");
      setState(() => _hasPurchased = false);
    } finally {
      if(mounted) setState(() => _isFetchingNotes = false);
    }
  }

  void _startPayment() async {
    if (_razorpayKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payment key load nahi hui. Please try again.")));
      return;
    }

    setState(() => _isFetchingNotes = true);
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('createRazorpayOrder');
      final result = await callable.call<Map<String, dynamic>>({
        'amount': 50, // Amount in Rupees
      });
      final String orderId = result.data['orderId'];

      var options = {
        'key': _razorpayKey, // Yahan remote config se aayi key use hogi
        'amount': 5000, // 50 INR in paise
        'name': 'Course Application',
        'order_id': orderId,
        'description': 'Access for ${_selectedClass!.name}',
        'prefill': {'email': FirebaseAuth.instance.currentUser?.email ?? ''}
      };
      _razorpay.open(options);
    } catch (e) {
      print("Error starting payment: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not start payment. Please try again.")));
    } finally {
      if (mounted) setState(() => _isFetchingNotes = false);
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    print("Payment Successful: ${response.paymentId}");
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('verifyRazorpayPayment');
      await callable.call({
        'orderId': response.orderId,
        'paymentId': response.paymentId,
        'signature': response.signature,
        'classId': _selectedClass!.id,
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payment successful! Access granted.")));
      setState(() => _hasPurchased = true);

    } catch (e) {
      print("Error verifying payment: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payment verification failed.")));
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    print("Payment Error: ${response.code} - ${response.message}");
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Payment failed: ${response.message}")));
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print("External Wallet: ${response.walletName}");
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select a Class"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<Class>(
              value: _selectedClass,
              hint: const Text("Choose a class"),
              isExpanded: true,
              items: _classes.map((Class item) {
                return DropdownMenuItem<Class>(
                  value: item,
                  child: Text(item.name),
                );
              }).toList(),
              onChanged: (Class? newValue) {
                setState(() {
                  _selectedClass = newValue;
                  _hasPurchased = false; // Reset purchase status on new selection
                });
                if (newValue != null) {
                  _checkIfPurchased();
                }
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              ),
            ),
            const SizedBox(height: 20),
            if (_selectedClass != null)
              _isFetchingNotes
                  ? const Center(child: CircularProgressIndicator())
                  : _hasPurchased
                  ? ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NotesDisplayScreen(classId: _selectedClass!.id),
                    ),
                  );
                },
                child: const Text("View Notes"),
              )
                  : ElevatedButton(
                onPressed: _startPayment,
                child: const Text("Unlock for ₹50"),
              ),
          ],
        ),
      ),
    );
  }
}