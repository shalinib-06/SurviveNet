import 'package:flutter/material.dart';

// --- Reusable Tag Widget (Skill, Status, Priority) ---
class CustomTag extends StatelessWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;

  const CustomTag({
    super.key,
    required this.text,
    required this.backgroundColor,
    this.textColor = Colors.white,
  });

  factory CustomTag.status(String status) {
    Color bgColor;
    Color textColor = Colors.white;
    switch (status.toLowerCase()) {
      case 'available':
      case 'active':
        bgColor = Colors.green.shade600;
        break;
      case 'verified':
        bgColor = Colors.blue.shade600;
        break;
      case 'busy':
      case 'standby':
        bgColor = Colors.orange.shade600;
        break;
      case 'full':
        bgColor = Colors.red.shade600;
        break;
      case 'high':
        bgColor = Colors.red.shade600;
        break;
      case 'medium':
        bgColor = Colors.orange.shade600;
        break;
      case 'low':
      default:
        bgColor = Colors.blueGrey;
        break;
    }
    return CustomTag(text: status, backgroundColor: bgColor, textColor: textColor);
  }

  factory CustomTag.skill(String skill) {
    return CustomTag(
      text: skill,
      backgroundColor: Colors.grey.shade200,
      textColor: Colors.black87,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// --- Reusable Volunteer/Team Card ---
class VolunteerCard extends StatelessWidget {
  final String name;
  final String description;
  final List<String> skills;
  final String status;
  final String distance;
  final String timeAgo;
  final double rating;
  final bool isVerified;
  final bool isTeam;
  final int? members;

  const VolunteerCard({
    super.key,
    required this.name,
    required this.description,
    required this.skills,
    required this.status,
    required this.distance,
    this.timeAgo = 'just now',
    this.rating = 5.0,
    this.isVerified = false,
    this.isTeam = false,
    this.members,
  });

  @override
  Widget build(BuildContext context) {
    // Determine Avatar Text
    String avatarText = isTeam ? 'ER' : name.split(' ').map((e) => e[0]).join();
    if (avatarText.length > 2) avatarText = avatarText.substring(0, 2);

    // Determine Avatar Color
    Color avatarColor = isTeam ? Colors.black : Colors.blueGrey;
    if (status.toLowerCase() == 'available') avatarColor = Colors.green.shade700;
    if (status.toLowerCase() == 'busy') avatarColor = Colors.orange.shade700;


    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar (Initials or Team Icon)
                CircleAvatar(
                  radius: 20,
                  backgroundColor: avatarColor,
                  child: Text(
                    isTeam ? '👥' : avatarText,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isTeam ? 18 : 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          if (isVerified)
                            Icon(Icons.check_circle,
                                color: Theme.of(context).canvasColor, size: 16),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '$rating',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '• $timeAgo',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                          if (members != null) ...[
                            const SizedBox(width: 8),
                            Text('• $members members',
                                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
                CustomTag.status(status),
              ],
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 10),
            // Skill Tags
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: skills.map((skill) => CustomTag.skill(skill)).toList(),
            ),
            const SizedBox(height: 12),
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(isTeam ? Icons.chat : Icons.phone),
                    label: Text(isTeam ? 'Contact Team' : 'Call'),
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.grey),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.message),
                    label: const Text('Message'),
                    onPressed: () {},
                    // Style inherited from main.dart
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}