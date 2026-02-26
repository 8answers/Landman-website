import 'package:flutter/material.dart';

class PartnerDropdown extends StatelessWidget {
  final List<String> partners = [
    'Lily Kimberley',
    'Shelly Fall',
    'Herman Das',
    'Harris Skylark',
    'Mark Henry',
  ];

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), // Matches filter popup padding
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), // Matches filter popup border radius
          borderSide: BorderSide(color: Color(0xFF5C5C5C), width: 0.5), // Matches filter popup border color and width
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.blue, width: 0.5),
        ),
      ),
      dropdownColor: Colors.white,
      elevation: 2, // Matches filter popup elevation
      items: partners.map((partner) {
        return DropdownMenuItem<String>(
          value: partner,
          child: Container(
            alignment: Alignment.centerLeft,
            height: 24, // Matches reduced height
            child: Text(
              partner,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: Color(0xFF000000),
                fontStyle: FontStyle.normal,
                height: 1.0,
              ),
            ),
          ),
        );
      }).toList(),
      onChanged: (value) {
        // Handle dropdown selection
      },
      hint: Text(
        'Select Partner(s)',
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: Colors.black,
        ),
      ),
      icon: Transform.scale(
        scale: 0.8,
        child: Transform.rotate(
          angle: -90 * 3.14159 / 180,
          child: Icon(
            Icons.arrow_back_ios,
            size: 12,
          ),
        ),
      ),
    );
  }
}