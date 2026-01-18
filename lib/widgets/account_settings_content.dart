import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'personal_details_card.dart';
import 'password_card.dart';

class AccountSettingsContent extends StatelessWidget {
  const AccountSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;
    
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 48,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Settings',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 28 : isTablet ? 32 : 36,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: isMobile ? double.infinity : 352,
                  height: 20,
                  child: Text(
                    'Manage your account information and security',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black.withOpacity(0.8),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            // Personal Details Card
            const PersonalDetailsCard(),
            const SizedBox(height: 40),
            // Password Card
            const PasswordCard(),
          ],
        ),
      ),
    );
  }
}

