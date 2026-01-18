import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ProjectSaveStatusType {
  saved,
  saving,
  connectionLost,
}

class ProjectSaveStatus extends StatelessWidget {
  final ProjectSaveStatusType status;
  final String? savedTimeAgo; // e.g., "2 minutes ago"

  const ProjectSaveStatus({
    super.key,
    required this.status,
    this.savedTimeAgo,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ProjectSaveStatusType.saved:
        return _buildSavedStatus();
      case ProjectSaveStatusType.saving:
        return _buildSavingStatus();
      case ProjectSaveStatusType.connectionLost:
        return _buildConnectionLostStatus();
    }
  }

  Widget _buildSavedStatus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF06AB00),
              height: 1.0,
            ),
            children: [
              const TextSpan(text: 'Project Saved ✓'),
              const TextSpan(text: '\n'),
              TextSpan(
                text: savedTimeAgo ?? '2 minutes ago',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSavingStatus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF0C8CE9),
              height: 1.0,
            ),
            children: [
              const TextSpan(text: 'Saving...'),
              const TextSpan(text: '\n'),
              TextSpan(
                text: 'Please keep this page open',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionLostStatus() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Waiting for network',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: Colors.red,
                ),
              ),
              Text(
                'Couldn\'t save',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Refresh/retry icon
        SizedBox(
          width: 18,
          height: 16,
          child: Icon(
            Icons.refresh,
            size: 16,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}

