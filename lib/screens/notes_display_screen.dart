import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// Yeh screen abhi tak project mein nahi hai, isko banana padega
// import 'pdf_screen_viewer.dart';

// Ek simple placeholder PDF viewer, jab tak aap asli wala nahi banate
class PdfViewerScreen extends StatelessWidget {
  final String pdfUrl;
  final String title;
  const PdfViewerScreen({super.key, required this.pdfUrl, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text('PDF URL: $pdfUrl'),
      ),
    );
  }
}


class Note {
  final String title;
  final String pdfUrl;
  final String chapterName;

  Note({required this.title, required this.pdfUrl, required this.chapterName});

  factory Note.fromFirestore(Map<String, dynamic> data) {
    return Note(
      title: data['fileName'] ?? 'No Title',
      pdfUrl: data['pdfUrl'] ?? '',
      chapterName: data['chapterName'] ?? 'No Chapter',
    );
  }
}

class NotesDisplayScreen extends StatefulWidget {
  // Yahan 'List<QueryDocumentSnapshot>' ki jagah 'String' lenge
  final String classId;

  const NotesDisplayScreen({super.key, required this.classId});

  @override
  State<NotesDisplayScreen> createState() => _NotesDisplayScreenState();
}

class _NotesDisplayScreenState extends State<NotesDisplayScreen> {
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotes();
  }

  // Yeh function classId ka istemal karke notes fetch karega
  Future<void> _fetchNotes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId) // Yahan widget.classId use karenge
          .collection('notes')
          .get();

      final notes = snapshot.docs
          .map((doc) => Note.fromFirestore(doc.data()))
          .toList();

      if (mounted) {
        setState(() {
          _notes = notes;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching notes: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not fetch notes.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Available Notes"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
          ? const Center(
        child: Text("Sorry, no notes found for this class."),
      )
          : ListView.builder(
        itemCount: _notes.length,
        itemBuilder: (context, index) {
          final note = _notes[index];
          return ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
            title: Text(note.title),
            subtitle: Text(note.chapterName),
            onTap: () {
              if (note.pdfUrl.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PdfViewerScreen(
                      pdfUrl: note.pdfUrl,
                      title: note.title,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Sorry, PDF link is not available!"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}