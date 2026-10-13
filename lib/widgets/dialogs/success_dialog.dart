import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SuccessDialog extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onPressed;

  const SuccessDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 50,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Continuar',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
