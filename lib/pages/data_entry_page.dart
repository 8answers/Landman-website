import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DataEntryPage extends StatelessWidget {
  const DataEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data Entry',
          style: GoogleFonts.inter(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter and manage project data.',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: Colors.black.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
}

